"""Yazici - novbeden mesajlari deste ile oxuyub bazaya yazir."""
import asyncio
import logging

import psycopg

from .baza import hovuz, HEDLER

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
SQL_XEBER = """
    INSERT INTO xeberdarliq (cihaz_kod, olcme_vaxti, qiymet, novu, mesaj)
    VALUES (%s, %s, %s, %s, %s)
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
    """Desteni BIR tranzaksiyada bazaya yazir."""
    olcme_setirleri = []
    xeber_setirleri = []

    for o in deste:
        if o.cihaz_kod not in HEDLER:
            log.warning("Namelum cihaz: %s - atildi", o.cihaz_kod)
            YAZICI_METRIKA["xeta"] += 1
            continue

        mn, mx, vahid = HEDLER[o.cihaz_kod]
        keyfiyyet = 1 if mn <= o.qiymet <= mx else 0

        olcme_setirleri.append((o.cihaz_kod, o.olcme_vaxti, o.qiymet, keyfiyyet))

        if o.qiymet > mx:
            xeber_setirleri.append((
                o.cihaz_kod, o.olcme_vaxti, o.qiymet, "yuxari_hedd",
                f"{o.cihaz_kod}: {o.qiymet} {vahid} > maks {mx}",
            ))
            YAZICI_METRIKA["anomal"] += 1
        elif o.qiymet < mn:
            xeber_setirleri.append((
                o.cihaz_kod, o.olcme_vaxti, o.qiymet, "asagi_hedd",
                f"{o.cihaz_kod}: {o.qiymet} {vahid} < min {mn}",
            ))
            YAZICI_METRIKA["anomal"] += 1

    if not olcme_setirleri:
        return

    try:
        async with hovuz.connection() as conn:
            async with conn.cursor() as cur:
                await cur.executemany(SQL_OLCME, olcme_setirleri)
                if xeber_setirleri:
                    await cur.executemany(SQL_XEBER, xeber_setirleri)

        YAZICI_METRIKA["yazilan"] += len(olcme_setirleri)
        YAZICI_METRIKA["batch"] += 1
        log.info("Deste yazildi: %d olcme, %d alert",
                 len(olcme_setirleri), len(xeber_setirleri))

    except psycopg.Error as e:
        YAZICI_METRIKA["xeta"] += len(olcme_setirleri)
        log.error("Baza xetasi, deste (%d) itdi: %s", len(olcme_setirleri), e)


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
