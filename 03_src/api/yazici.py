"""Yazici - novbeden desteni oxuyur, bazaya yazir, alert muherrikini isledir."""
import asyncio
import logging

import psycopg

from .baza import hovuz, HEDLER
from . import alert as alert_modul
from .bildiris import bildiris_gonder

log = logging.getLogger("zarat.yazici")

BATCH_OLCU = 100
BATCH_VAXT = 2.0

YAZICI_METRIKA = {"yazilan": 0, "anomal": 0,
                  "dublikat": 0, "xeta": 0, "batch": 0}

SQL_OLCME = """
    INSERT INTO olcme (cihaz_kod, olcme_vaxti, qiymet, keyfiyyet)
    VALUES (%s, %s, %s, %s)
    ON CONFLICT (cihaz_kod, olcme_vaxti) DO NOTHING
"""


async def deste_topla(novbe):
    """Ya BATCH_OLCU mesaj yigilana, ya BATCH_VAXT kecene qeder."""
    deste = [await novbe.get()]
    son_vaxt = asyncio.get_running_loop().time() + BATCH_VAXT
    while len(deste) < BATCH_OLCU:
        qalan = son_vaxt - asyncio.get_running_loop().time()
        if qalan <= 0:
            break
        try:
            deste.append(await asyncio.wait_for(novbe.get(), timeout=qalan))
        except asyncio.TimeoutError:
            break
    return deste


async def deste_yaz(deste):
    """Desteni bir tranzaksiyada yazir + alert muherrikini isledir."""
    olcme_setirleri = []
    emrler = []

    # ---- 1. Qiymetlendir (bazasiz, suretli) ----
    for o in deste:
        h = HEDLER.get(o.cihaz_kod)
        if h is None:
            log.warning("Namelum cihaz: %s", o.cihaz_kod)
            YAZICI_METRIKA["xeta"] += 1
            continue

        keyfiyyet = 1 if h["min"] <= o.qiymet <= h["max"] else 0
        olcme_setirleri.append((o.cihaz_kod, o.olcme_vaxti, o.qiymet, keyfiyyet))
        if keyfiyyet == 0:
            YAZICI_METRIKA["anomal"] += 1

        # Alert muherriki - QERAR verir, yazmir
        emrler.append(alert_modul.qiymetlendir(
            o.cihaz_kod, o.qiymet, o.olcme_vaxti))

    if not olcme_setirleri:
        return

    yeni_kritikler = []

    # ---- 2. Bir tranzaksiyada her seyi yaz ----
    try:
        async with hovuz.connection() as conn:
            async with conn.cursor() as cur:
                await cur.executemany(SQL_OLCME, olcme_setirleri)

            for emr in emrler:
                if emr.emr == "ac_ve_ya_yenile":
                    netice = await alert_modul.alerti_yaz(conn, emr)
                    if netice and netice["yeni"] and netice["seviyye"] == "kritik":
                        yeni_kritikler.append(emr)
                elif emr.emr == "bagla":
                    await alert_modul.alertleri_bagla(conn, emr)

        YAZICI_METRIKA["yazilan"] += len(olcme_setirleri)
        YAZICI_METRIKA["batch"] += 1

    except psycopg.Error as e:
        YAZICI_METRIKA["xeta"] += len(olcme_setirleri)
        log.error("Baza xetasi, deste (%d) itdi: %s", len(olcme_setirleri), e)
        return

    # ---- 3. Bildiris TRANZAKSIYADAN SONRA ----
    for emr in yeni_kritikler:
        await bildiris_gonder(baslik=f"KRITIK: {emr.cihaz_kod}", metn=emr.mesaj)


async def yazici_dovru(novbe):
    """Sonsuz dovr - OLMEMELIDIR."""
    log.info("Yazici basladi (batch=%d, vaxt=%.1fs)", BATCH_OLCU, BATCH_VAXT)
    while True:
        try:
            deste = await deste_topla(novbe)
            await deste_yaz(deste)
            for _ in deste:
                novbe.task_done()
        except asyncio.CancelledError:
            log.info("Yazici dayandirilir...")
            raise
        except Exception as e:
            log.exception("Yazicida gozlenilmez xeta: %s", e)
            await asyncio.sleep(1)
