"""
Sync isciisi - ayrica proses.
Isledilir: python 03_src/sync/main.py
"""
import asyncio
import logging
import signal
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sync.konfiq import SYNC_INTERVAL, ZAVOD_KOD, VERSIYA
from sync.baza import ac, bagla, merkez_elcatandir
from sync.backoff import Backoff
from sync.olcme_sync import olcme_gonder, OLCME_METRIKA
from sync.alert_sync import alert_gonder, ALERT_METRIKA
from sync.sened_sync import sened_gonder, SENED_METRIKA
from sync.fayl_sync import fayl_gonder, FAYL_METRIKA

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)-7s] %(name)-12s | %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("sync")

dayan = asyncio.Event()


async def gozle(saniye: float) -> None:
    """Dayanma siqnali gelse, derhal cixir."""
    try:
        await asyncio.wait_for(dayan.wait(), timeout=saniye)
    except asyncio.TimeoutError:
        pass


async def bir_dovr(backoff: Backoff) -> None:
    try:
        # PRİORİTET SIRASI: alert → sənəd → ölçmə → fayl
        # (Kritik məlumat böyük faylların arxasında gözləməsin)
        alert_say = await alert_gonder()
        sened_say = await sened_gonder()
        olcme_say = await olcme_gonder()

        if backoff.problemdedir:
            log.info("MERKEZ BERPA OLUNDU (%d ugursuz cehdden sonra)",
                     backoff.ugursuz_say)
        backoff.ugurlu()

        # Növbə hələ doludur — GÖZLƏMƏDƏN davam et
        if alert_say >= 1 or sened_say >= 1 or olcme_say >= 1:
            return

    except Exception as e:
        gozleme = backoff.ugursuz()
        log.error("Sync ugursuz (#%d): %s - %.1f san. gozleyirem",
                  backoff.ugursuz_say, e, gozleme)
        await gozle(gozleme)
        return

    # Fayl sync ayrıca cəhd: MinIO xətası DB sync-i dayandırmasın
    try:
        await fayl_gonder()
    except Exception as e:
        log.warning("Fayl sync xətası (davam edir): %s", e)

    await gozle(SYNC_INTERVAL)


async def esas():
    log.info("Sync isciisi baslayir - zavod=%s, versiya=%s", ZAVOD_KOD, VERSIYA)
    await ac()

    if await merkez_elcatandir():
        log.info("Merkez elcatandir")
    else:
        log.warning("Merkez ELCATMAZDIR - gozleyecek, data itmeyecek")

    backoff = Backoff(bas=1.0, tavan=300.0)

    while not dayan.is_set():
        await bir_dovr(backoff)

    log.info("Sonme... Metrikalar:")
    log.info("  Alert:  %s", ALERT_METRIKA)
    log.info("  Sened:  %s", SENED_METRIKA)
    log.info("  Olcme:  %s", OLCME_METRIKA)
    log.info("  Fayl:   %s", FAYL_METRIKA)
    await bagla()
    log.info("Sync isciisi sondu.")


def signal_tut():
    log.info("Dayandirma siqnali alindi...")
    dayan.set()


if __name__ == "__main__":
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, signal_tut)

    try:
        loop.run_until_complete(esas())
    finally:
        loop.close()
