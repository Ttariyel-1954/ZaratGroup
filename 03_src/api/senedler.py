"""
Sənəd endpointləri — Faza 3.
Fayl qəbul et → SHA-256 hesabla → MinIO-ya yüklə → bazaya yaz.
"""
import asyncio
import hashlib
import logging
import uuid
from datetime import date, datetime, timezone
from io import BytesIO
from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, Query, UploadFile
from minio import Minio
from minio.error import S3Error

from .baza import hovuz
from .konfiq import (
    MINIO_ACCESS_KEY, MINIO_BUCKET, MINIO_EDGE_URL,
    MINIO_SECRET_KEY, ZAVOD_KOD,
)

log = logging.getLogger("zarat.sened")

router = APIRouter(prefix="/senedler", tags=["Sənəd"])

# İcazə verilən MIME tipləri
ICAZE_MIMELERI = {
    "application/pdf",
    "image/jpeg",
    "image/png",
    "image/tiff",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
}

MAX_OLCU_BAYT = 20 * 1024 * 1024  # 20 MB


def _minio_muşteri() -> Minio:
    """MinIO müştərisi yaradır. Hər çağırışda yeni obyekt — thread-safe."""
    endpoint = (
        MINIO_EDGE_URL
        .replace("https://", "")
        .replace("http://", "")
    )
    secure = MINIO_EDGE_URL.startswith("https://")
    return Minio(
        endpoint,
        access_key=MINIO_ACCESS_KEY,
        secret_key=MINIO_SECRET_KEY,
        secure=secure,
    )


def _bucket_yarat_ehtiyac_olarsa(mc: Minio) -> None:
    """Bucket yoxdursa yaradır (idemponent)."""
    if not mc.bucket_exists(MINIO_BUCKET):
        mc.make_bucket(MINIO_BUCKET)
        log.info("MinIO bucket yaradıldı: %s", MINIO_BUCKET)


async def _minio_yukle(mc: Minio, acari: str, melumat: bytes, mime: str) -> None:
    """Sinxron MinIO çağırışını thread hovuzunda icra edir."""
    def _yukle():
        _bucket_yarat_ehtiyac_olarsa(mc)
        mc.put_object(
            MINIO_BUCKET,
            acari,
            BytesIO(melumat),
            length=len(melumat),
            content_type=mime,
        )
    await asyncio.to_thread(_yukle)


# ============================================================
# POST /senedler/yukle
# ============================================================

@router.post("/yukle", status_code=201)
async def sened_yukle(
    fayl:          UploadFile = File(...,  description="PDF, şəkil və ya Excel"),
    novu:          str        = Form("QAIME",    description="Sənəd növü"),
    nomre:         str | None = Form(None,       description="Zavodun daxili nömrəsi"),
    sened_tarixi:  str | None = Form(None,       description="Sənədin tarixi (YYYY-MM-DD)"),
    qarsi_teref:   str | None = Form(None,       description="Təchizatçı / müştəri"),
    qeyd:          str | None = Form(None,       description="Sərbəst qeyd"),
    daxil_eden:    str        = Form("operator", description="Kim daxil etdi"),
):
    """
    Sənədi qəbul edir:
    1. Faylı oxuyur, SHA-256 hesablayır
    2. MinIO edge-ə yükləyir
    3. `sened` + `sened_fayl` cədvəllərinə yazır
    4. sened_id, fayl_id, sha256 prefix qaytarır
    """
    # ---- Yoxlamalar ----
    mime = fayl.content_type or "application/octet-stream"
    if mime not in ICAZE_MIMELERI:
        raise HTTPException(
            status_code=415,
            detail=f"İcazəsiz fayl tipi: {mime}. "
                   f"İcazə verilənlər: {sorted(ICAZE_MIMELERI)}",
        )

    melumat = await fayl.read()

    if len(melumat) > MAX_OLCU_BAYT:
        raise HTTPException(
            status_code=413,
            detail=f"Fayl həddindən böyükdür: "
                   f"{len(melumat)//1024//1024} MB > 20 MB",
        )
    if len(melumat) == 0:
        raise HTTPException(status_code=400, detail="Fayl boşdur.")

    # ---- SHA-256 ----
    sha256 = hashlib.sha256(melumat).hexdigest()

    # ---- MinIO obyekt açarı: SIYEZEN/2026/07/13/<uuid>.<uzantı> ----
    bugun  = datetime.now(timezone.utc)
    uzanti = Path(fayl.filename or "fayl.bin").suffix.lower() or ".bin"
    acari  = f"{ZAVOD_KOD}/{bugun.strftime('%Y/%m/%d')}/{uuid.uuid4().hex}{uzanti}"

    # ---- MinIO-ya yüklə ----
    try:
        mc = _minio_muşteri()
        await _minio_yukle(mc, acari, melumat, mime)
        log.info("MinIO-ya yükləndi: %s (%d bayt)", acari, len(melumat))
    except S3Error as e:
        log.error("MinIO S3 xətası: %s", e)
        raise HTTPException(status_code=503, detail=f"MinIO xətası: {e.code}")
    except Exception as e:
        log.error("MinIO bağlantı xətası: %s", e)
        raise HTTPException(status_code=503,
                            detail="MinIO əlçatmazdır. Servisi yoxlayın.")

    # ---- Tarix çevir ----
    tarix: date | None = None
    if sened_tarixi:
        try:
            tarix = date.fromisoformat(sened_tarixi)
        except ValueError:
            pass  # Yanlış format — NULL saxla

    # ---- Baza ----
    async with hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO sened
                    (novu, nomre, sened_tarixi, qarsi_teref, qeyd,
                     daxil_eden, menbe, status)
                VALUES (%s, %s, %s, %s, %s, %s, 'FAYL', 'qaralama')
                RETURNING id
                """,
                (novu, nomre, tarix, qarsi_teref, qeyd, daxil_eden),
            )
            sened_id: int = (await cur.fetchone())[0]

            await cur.execute(
                """
                INSERT INTO sened_fayl
                    (sened_id, orijinal_ad, mime_tipi, olcu_bayt,
                     obyekt_acari, sha256)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING id
                """,
                (sened_id, fayl.filename, mime,
                 len(melumat), acari, sha256),
            )
            fayl_id: int = (await cur.fetchone())[0]

    log.info("Sənəd yazıldı: sened_id=%d, fayl_id=%d", sened_id, fayl_id)

    return {
        "sened_id":     sened_id,
        "fayl_id":      fayl_id,
        "obyekt_acari": acari,
        "sha256_prefix": sha256[:16] + "...",
        "olcu_bayt":    len(melumat),
        "status":       "qaralama",
    }


# ============================================================
# GET /senedler/
# ============================================================

@router.get("/")
async def sened_siyahisi(
    limit:  int       = Query(50, ge=1, le=500),
    novu:   str | None = Query(None),
    status: str | None = Query(None),
):
    """Sənəd siyahısı (ən yenilər önce)."""
    filterlər: list[str] = []
    params:    list      = []

    if novu:
        filterlər.append("novu = %s")
        params.append(novu)
    if status:
        filterlər.append("status = %s")
        params.append(status)

    where = f"WHERE {' AND '.join(filterlər)}" if filterlər else ""
    params.append(limit)

    async with hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                f"""
                SELECT s.id, s.novu, s.nomre, s.sened_tarixi,
                       s.qarsi_teref, s.status, s.daxil_eden,
                       s.yaradilma_vaxti,
                       count(f.id) AS fayl_sayi
                FROM sened s
                LEFT JOIN sened_fayl f ON f.sened_id = s.id
                {where}
                GROUP BY s.id
                ORDER BY s.id DESC
                LIMIT %s
                """,
                params,
            )
            setirler = await cur.fetchall()

    return [
        {
            "id":             r[0],
            "novu":           r[1],
            "nomre":          r[2],
            "sened_tarixi":   r[3],
            "qarsi_teref":    r[4],
            "status":         r[5],
            "daxil_eden":     r[6],
            "yaradilma_vaxti": r[7],
            "fayl_sayi":      r[8],
        }
        for r in setirler
    ]


# ============================================================
# GET /senedler/sync-veziyyet
# ============================================================

@router.get("/sync-veziyyet")
async def sync_veziyyet():
    """Sinxronizasiya növbəsinin vəziyyəti (panel üçün)."""
    async with hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute("SELECT * FROM sened_sync_veziyyet")
            setir = await cur.fetchone()

    if setir is None:
        return {}
    return {
        "sened_novbede":  setir[0],
        "fayl_novbede":   setir[1],
        "novbede_bayt":   setir[2],
        "problemli_fayl": setir[3],
    }
