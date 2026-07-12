"""Olcme sinxronizasiyasi - deyismez faktlar, DO NOTHING."""
import logging
import time

from .baza import edge_hovuz, merkez_hovuz
from .konfiq import ZAVOD_KOD, SYNC_BATCH_OLCME

log = logging.getLogger("sync.olcme")

OLCME_METRIKA = {"gonderilen": 0, "yeni": 0, "dublikat": 0, "dovr": 0}

# KOHNEDEN yeniye - FIFO
SQL_SEC = """
    SELECT id, cihaz_kod, olcme_vaxti, qiymet, keyfiyyet
    FROM olcme
    WHERE sync_status = 0
    ORDER BY olcme_vaxti
    LIMIT %s
"""

# IDEMPOTENT: tekrar gonderilse, sessizce atilir
SQL_MERKEZ = """
    INSERT INTO zavod.olcme
        (zavod_kod, cihaz_kod, olcme_vaxti, qiymet, keyfiyyet)
    VALUES (%s, %s, %s, %s, %s)
    ON CONFLICT (zavod_kod, cihaz_kod, olcme_vaxti) DO NOTHING
"""

SQL_BAYRAQ = "UPDATE olcme SET sync_status = 1 WHERE id = ANY(%s)"

SQL_JURNAL = """
    INSERT INTO zavod.sync_jurnal
        (zavod_kod, cedvel, setir_sayi, yeni_setir, muddet_ms)
    VALUES (%s, 'olcme', %s, %s, %s)
"""


async def olcme_gonder() -> int:
    """Bir dovr. Qaytarir: gonderilen setir sayi. ISTISNA ATIR."""
    baslangic = time.monotonic()

    # ---- 1. Edge-den oxu ----
    async with edge_hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(SQL_SEC, (SYNC_BATCH_OLCME,))
            setirler = await cur.fetchall()

    if not setirler:
        return 0

    idler = [r[0] for r in setirler]
    merkez_setirler = [(ZAVOD_KOD, r[1], r[2], r[3], r[4]) for r in setirler]

    # ---- 2. MERKEZE yaz (istisna ata biler!) ----
    async with merkez_hovuz.connection() as mconn:
        async with mconn.cursor() as mcur:
            await mcur.executemany(SQL_MERKEZ, merkez_setirler)
            yeni_say = mcur.rowcount if mcur.rowcount >= 0 else len(setirler)

            muddet_ms = int((time.monotonic() - baslangic) * 1000)
            await mcur.execute(SQL_JURNAL,
                               (ZAVOD_KOD, len(setirler), yeni_say, muddet_ms))
        # commit avtomatik

    # ---- 3. YALNIZ INDI bayragi deyis ----
    async with edge_hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(SQL_BAYRAQ, (idler,))

    dublikat = max(0, len(setirler) - yeni_say)
    OLCME_METRIKA["gonderilen"] += len(setirler)
    OLCME_METRIKA["yeni"] += yeni_say
    OLCME_METRIKA["dublikat"] += dublikat
    OLCME_METRIKA["dovr"] += 1

    log.info("Olcme: %d gonderildi (%d yeni, %d dublikat) - %d ms",
             len(setirler), yeni_say, dublikat,
             int((time.monotonic() - baslangic) * 1000))

    return len(setirler)
