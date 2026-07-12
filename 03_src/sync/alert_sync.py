"""Alert sinxronizasiyasi - yasayan veziyyet, DO UPDATE."""
import logging
import time

from .baza import edge_hovuz, merkez_hovuz
from .konfiq import ZAVOD_KOD, SYNC_BATCH_ALERT, SYNC_ALERT_TEKRAR

log = logging.getLogger("sync.alert")

ALERT_METRIKA = {"gonderilen": 0, "yeni": 0, "yenilenen": 0, "dovr": 0}

# KRITIKLER ONDE + "hot setir" mudafiesi
SQL_SEC = """
    SELECT id, cihaz_kod, novu, seviyye, mesaj,
           acilma_vaxti, baglanma_vaxti, tetik_sayi,
           ilk_qiymet, son_qiymet, pik_qiymet, hell_olundu
    FROM xeberdarliq
    WHERE sync_status = 0
      AND (
          sync_vaxti IS NULL
          OR sync_vaxti < now() - (%s || ' seconds')::interval
      )
    ORDER BY (seviyye = 'kritik') DESC, acilma_vaxti
    LIMIT %s
"""

SQL_MERKEZ = """
    INSERT INTO zavod.xeberdarliq (
        zavod_kod, edge_id, cihaz_kod, novu, seviyye, mesaj,
        acilma_vaxti, baglanma_vaxti, tetik_sayi,
        ilk_qiymet, son_qiymet, pik_qiymet, hell_olundu
    )
    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    ON CONFLICT (zavod_kod, edge_id) DO UPDATE SET
        seviyye        = EXCLUDED.seviyye,
        mesaj          = EXCLUDED.mesaj,
        baglanma_vaxti = EXCLUDED.baglanma_vaxti,
        tetik_sayi     = EXCLUDED.tetik_sayi,
        son_qiymet     = EXCLUDED.son_qiymet,
        pik_qiymet     = EXCLUDED.pik_qiymet,
        hell_olundu    = EXCLUDED.hell_olundu,
        qebul_vaxti    = now()
    RETURNING (xmax = 0) AS yeni
"""

SQL_BAYRAQ = """
    UPDATE xeberdarliq
    SET sync_status = 1, sync_vaxti = now()
    WHERE id = ANY(%s)
"""


async def alert_gonder() -> int:
    """Bir dovr. ISTISNA ATIR."""
    baslangic = time.monotonic()

    async with edge_hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(SQL_SEC, (SYNC_ALERT_TEKRAR, SYNC_BATCH_ALERT))
            setirler = await cur.fetchall()

    if not setirler:
        return 0

    idler = [r[0] for r in setirler]
    yeni_say = 0

    async with merkez_hovuz.connection() as mconn:
        async with mconn.cursor() as mcur:
            for r in setirler:
                await mcur.execute(SQL_MERKEZ, (
                    ZAVOD_KOD, r[0], r[1], r[2], r[3], r[4],
                    r[5], r[6], r[7], r[8], r[9], r[10], r[11],
                ))
                netice = await mcur.fetchone()
                if netice and netice[0]:
                    yeni_say += 1

    async with edge_hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(SQL_BAYRAQ, (idler,))

    ALERT_METRIKA["gonderilen"] += len(setirler)
    ALERT_METRIKA["yeni"] += yeni_say
    ALERT_METRIKA["yenilenen"] += len(setirler) - yeni_say
    ALERT_METRIKA["dovr"] += 1

    log.info("Alert: %d gonderildi (%d yeni, %d yenilendi) - %d ms",
             len(setirler), yeni_say, len(setirler) - yeni_say,
             int((time.monotonic() - baslangic) * 1000))

    return len(setirler)
