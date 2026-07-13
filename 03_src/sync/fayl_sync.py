"""
Fayl sinxronizasiyası — edge MinIO → mərkəz MinIO.

Axın:
  1. Edge DB-dən gözləyən faylları seç (batch=5)
  2. Hər fayl üçün:
     a) Edge MinIO-dan endir
     b) SHA-256 yoxla — uyğun gəlmirsə faylı ATLA (korrupsiya)
     c) Mərkəz MinIO-ya yüklə
     d) Mərkəz DB-yə zavod_sened.fayl yazısı (idempotent)
     e) Edge-də sync_status = 1
  3. Xəta baş verərsə → sync_cehd_sayi artır, son_xeta yazılır
     3+ cəhd uğursuz olan fayl paneldə xəbərdarlıq verir.

MinIO çağırışları sinxrondur → asyncio.to_thread() ilə icraa edilir.
"""
import asyncio
import hashlib
import logging
import time
from io import BytesIO

from minio import Minio
from minio.error import S3Error

from .baza import edge_hovuz, merkez_hovuz
from .konfiq import (
    MINIO_ACCESS_KEY, MINIO_BUCKET, MINIO_EDGE_URL,
    MINIO_MERKEZ_URL, MINIO_SECRET_KEY,
    SYNC_BATCH_FAYL, ZAVOD_KOD,
)

log = logging.getLogger("sync.fayl")

FAYL_METRIKA = {
    "gonderilen": 0, "xeta": 0, "sha_uygunsuz": 0,
    "dovr": 0, "atilan": 0,
}

# Çox uğursuz cəhd olan faylları artıq götürmə
MAX_CEHD = 10

SQL_SEC = """
    SELECT f.id, f.sened_id, f.orijinal_ad, f.mime_tipi,
           f.olcu_bayt, f.obyekt_acari, f.sha256
    FROM sened_fayl f
    WHERE f.sync_status = 0
      AND f.sync_cehd_sayi < %s
    ORDER BY f.id
    LIMIT %s
"""

# Mərkəzdəki sened_id-ni tap — sened_sync artıq göndərmişdirsə mövcuddur
SQL_MERKEZ_SENED_ID = """
    SELECT id FROM zavod_sened.sened
    WHERE zavod_kod = %s AND edge_id = %s
"""

# Fayl metadatasını mərkəzə yaz (idempotent)
SQL_MERKEZ_FAYL = """
    INSERT INTO zavod_sened.fayl (
        zavod_kod, edge_id, sened_id,
        orijinal_ad, mime_tipi, olcu_bayt,
        obyekt_acari, sha256, sha256_yoxlandi
    ) VALUES (
        %s, %s, %s,
        %s, %s, %s,
        %s, %s, TRUE
    )
    ON CONFLICT (zavod_kod, edge_id) DO UPDATE SET
        sha256_yoxlandi = TRUE,
        qebul_vaxti     = now()
"""

SQL_UGURLU = """
    UPDATE sened_fayl
    SET sync_status = 1, sync_vaxti = now()
    WHERE id = %s
"""

SQL_XETA = """
    UPDATE sened_fayl
    SET sync_cehd_sayi = sync_cehd_sayi + 1,
        son_xeta       = %s
    WHERE id = %s
"""


def _minio_al(url: str) -> Minio:
    endpoint = url.replace("https://", "").replace("http://", "")
    secure   = url.startswith("https://")
    return Minio(endpoint,
                 access_key=MINIO_ACCESS_KEY,
                 secret_key=MINIO_SECRET_KEY,
                 secure=secure)


def _fayl_kocur(
    edge_url: str,
    merkez_url: str,
    bucket: str,
    acari: str,
    beklenen_sha: str,
) -> tuple[str, int]:
    """
    Sinxron — asyncio.to_thread() icindən çağırılır.
    Returns: (faktiki_sha256, olcu_bayt)
    Raises: ValueError — SHA uyğunsuzdur
            S3Error    — MinIO xətası
    """
    mc_e = _minio_al(edge_url)
    mc_m = _minio_al(merkez_url)

    # Edge-dən endir
    cavab   = mc_e.get_object(bucket, acari)
    melumat = cavab.read()
    cavab.close()
    cavab.release_conn()

    # SHA-256 yoxla
    faktiki = hashlib.sha256(melumat).hexdigest()
    if faktiki != beklenen_sha:
        raise ValueError(
            f"SHA uyğunsuzluğu: gözlənilən={beklenen_sha[:8]}... "
            f"faktiki={faktiki[:8]}..."
        )

    # Mərkəzə yüklə — bucket olmaya bilər, idemponent yarat
    if not mc_m.bucket_exists(bucket):
        mc_m.make_bucket(bucket)

    mc_m.put_object(
        bucket,
        acari,
        BytesIO(melumat),
        length=len(melumat),
    )

    return faktiki, len(melumat)


async def fayl_gonder() -> int:
    """
    Bir dövr.  Qaytarır: uğurla göndərilən fayl sayı.
    MinIO əlçatmazdırsa — istisna ATMAZ, xəta yazır və davam edir.
    """
    baslangic = time.monotonic()

    # ---- 1. Edge-dən fayl siyahısı ----
    async with edge_hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(SQL_SEC, (MAX_CEHD, SYNC_BATCH_FAYL))
            setirler = await cur.fetchall()

    if not setirler:
        return 0

    ugurlu_say = 0
    FAYL_METRIKA["dovr"] += 1

    for r in setirler:
        (fayl_id, edge_sened_id, orijinal_ad, mime,
         olcu, acari, sha256) = r

        # ---- 2. Mərkəz sened_id-ni tap ----
        merkez_sened_id: int | None = None
        try:
            async with merkez_hovuz.connection(timeout=5.0) as mconn:
                async with mconn.cursor() as mcur:
                    await mcur.execute(
                        SQL_MERKEZ_SENED_ID, (ZAVOD_KOD, edge_sened_id)
                    )
                    netice = await mcur.fetchone()
                    if netice:
                        merkez_sened_id = netice[0]
        except Exception as e:
            # Mərkəz əlçatmazdır — bu dövrü tamamilə bitir
            log.warning("Fayl sync: mərkəz DB əlçatmazdır: %s", e)
            return ugurlu_say

        if merkez_sened_id is None:
            # Sənəd metadata hələ sinxronlaşmayıb — gözlə
            log.debug(
                "Fayl %d üçün sənəd hələ mərkəzdə yoxdur (edge_sened_id=%d) — atılır",
                fayl_id, edge_sened_id,
            )
            FAYL_METRIKA["atilan"] += 1
            continue

        # ---- 3. MinIO köçürmə (to_thread — sinxron çağırış) ----
        try:
            faktiki_sha, _ = await asyncio.to_thread(
                _fayl_kocur,
                MINIO_EDGE_URL,
                MINIO_MERKEZ_URL,
                MINIO_BUCKET,
                acari,
                sha256,
            )
        except ValueError as e:
            # SHA uyğunsuzluğu — fayl korrupsiyası, xəta yaz, atla
            log.error("SHA uyğunsuzluğu: fayl_id=%d, %s", fayl_id, e)
            FAYL_METRIKA["sha_uygunsuz"] += 1
            async with edge_hovuz.connection() as conn:
                async with conn.cursor() as cur:
                    await cur.execute(SQL_XETA, (str(e)[:500], fayl_id))
            continue
        except (S3Error, Exception) as e:
            log.error("MinIO xətası: fayl_id=%d: %s", fayl_id, e)
            FAYL_METRIKA["xeta"] += 1
            async with edge_hovuz.connection() as conn:
                async with conn.cursor() as cur:
                    await cur.execute(SQL_XETA, (str(e)[:500], fayl_id))
            continue

        # ---- 4. Mərkəz DB-yə yaz ----
        try:
            async with merkez_hovuz.connection() as mconn:
                async with mconn.cursor() as mcur:
                    await mcur.execute(
                        SQL_MERKEZ_FAYL,
                        (ZAVOD_KOD, fayl_id, merkez_sened_id,
                         orijinal_ad, mime, olcu,
                         acari, sha256),
                    )
        except Exception as e:
            log.error("Mərkəz DB yazma xətası: fayl_id=%d: %s", fayl_id, e)
            FAYL_METRIKA["xeta"] += 1
            async with edge_hovuz.connection() as conn:
                async with conn.cursor() as cur:
                    await cur.execute(SQL_XETA, (str(e)[:500], fayl_id))
            continue

        # ---- 5. YALNIZ ONDAN SONRA bayrağı dəyiş ----
        async with edge_hovuz.connection() as conn:
            async with conn.cursor() as cur:
                await cur.execute(SQL_UGURLU, (fayl_id,))

        ugurlu_say += 1
        FAYL_METRIKA["gonderilen"] += 1
        log.info(
            "Fayl göndərildi: fayl_id=%d, %s (%d bayt)",
            fayl_id, acari, olcu,
        )

    muddet_ms = int((time.monotonic() - baslangic) * 1000)
    if ugurlu_say:
        log.info(
            "Fayl dövrü: %d/%d uğurlu — %d ms",
            ugurlu_say, len(setirler), muddet_ms,
        )

    return ugurlu_say
