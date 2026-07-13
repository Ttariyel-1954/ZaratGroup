"""
Sənəd metadata sinxronizasiyası — edge → mərkəz.

Eyni olcme_sync.py nümunəsi:
  1. Edge-dən oxu
  2. Mərkəzə yaz (ON CONFLICT DO UPDATE — sənəd dəyişə bilər)
  3. YALNIZ ONDAN SONRA sync_status = 1 et
"""
import logging
import time

from .baza import edge_hovuz, merkez_hovuz
from .konfiq import ZAVOD_KOD, SYNC_BATCH_SENED

log = logging.getLogger("sync.sened")

SENED_METRIKA = {"gonderilen": 0, "yeni": 0, "yenilenen": 0, "dovr": 0}

# Edge-dən gözləyənləri gətir — köhnəsi əvvəl (FIFO)
SQL_SEC = """
    SELECT id, novu, nomre, sened_tarixi, qarsi_teref, qeyd,
           daxil_eden, menbe, status, metadata,
           yaradilma_vaxti, deyisme_vaxti
    FROM sened
    WHERE sync_status = 0
    ORDER BY id
    LIMIT %s
"""

# İdempotent: eyni (zavod_kod, edge_id) ikinci dəfə gəlsə — statusu yenilə
SQL_MERKEZ = """
    INSERT INTO sened.sened (
        zavod_kod, edge_id,
        novu, nomre, sened_tarixi, qarsi_teref, qeyd,
        daxil_eden, menbe, status, metadata,
        yaradilma_vaxti, deyisme_vaxti
    ) VALUES (
        %s, %s,
        %s, %s, %s, %s, %s,
        %s, %s, %s, %s,
        %s, %s
    )
    ON CONFLICT (zavod_kod, edge_id) DO UPDATE SET
        status        = EXCLUDED.status,
        nomre         = EXCLUDED.nomre,
        qarsi_teref   = EXCLUDED.qarsi_teref,
        qeyd          = EXCLUDED.qeyd,
        metadata      = EXCLUDED.metadata,
        deyisme_vaxti = EXCLUDED.deyisme_vaxti,
        qebul_vaxti   = now()
    RETURNING (xmax = 0) AS yeni
"""

# Yalnız uğurlu göndərişdən SONRA bayrağı dəyiş
SQL_BAYRAQ = """
    UPDATE sened
    SET sync_status = 1, sync_vaxti = now()
    WHERE id = ANY(%s)
"""


async def sened_gonder() -> int:
    """
    Bir dövr.  Qaytarır: göndərilən sənəd sayı.
    Mərkəz əlçatmazdırsa — istisna atır (main.py backoff idarə edir).
    """
    baslangic = time.monotonic()

    # ---- 1. Edge-dən oxu ----
    async with edge_hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(SQL_SEC, (SYNC_BATCH_SENED,))
            setirler = await cur.fetchall()

    if not setirler:
        return 0

    idler   = [r[0] for r in setirler]
    yeni    = 0
    yenilen = 0

    # ---- 2. Mərkəzə yaz ----
    async with merkez_hovuz.connection() as mconn:
        async with mconn.cursor() as mcur:
            for r in setirler:
                await mcur.execute(
                    SQL_MERKEZ,
                    (ZAVOD_KOD, r[0],          # zavod_kod, edge_id
                     r[1], r[2], r[3], r[4], r[5],   # novu..qeyd
                     r[6], r[7], r[8], r[9],          # daxil_eden..metadata
                     r[10], r[11]),                    # yaradilma, deyisme
                )
                netice = await mcur.fetchone()
                if netice and netice[0]:
                    yeni += 1
                else:
                    yenilen += 1
        # autocommit tətbiq edilir

    # ---- 3. YALNIZ ONDAN SONRA bayrağı dəyiş ----
    async with edge_hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(SQL_BAYRAQ, (idler,))

    muddet_ms = int((time.monotonic() - baslangic) * 1000)
    SENED_METRIKA["gonderilen"] += len(setirler)
    SENED_METRIKA["yeni"]       += yeni
    SENED_METRIKA["yenilenen"]  += yenilen
    SENED_METRIKA["dovr"]       += 1

    log.info(
        "Sənəd: %d göndərildi (%d yeni, %d yeniləndi) — %d ms",
        len(setirler), yeni, yenilen, muddet_ms,
    )
    return len(setirler)
