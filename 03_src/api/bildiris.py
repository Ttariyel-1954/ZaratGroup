"""Bildiris qati - kritik alertleri operatora catdirir."""
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

log = logging.getLogger("zarat.bildiris")

KOK = Path(__file__).resolve().parents[2]
BILDIRIS_FAYL = KOK / "_LOG" / "bildiris.log"

TELEGRAM_TOKEN = os.getenv("TELEGRAM_TOKEN", "")
TELEGRAM_CHAT = os.getenv("TELEGRAM_CHAT_ID", "")

BILDIRIS_METRIKA = {"gonderilen": 0, "xeta": 0}


async def bildiris_gonder(baslik: str, metn: str) -> None:
    """
    Kritik hadiseni operatora catdirir.
    XETA ATMAMALIDIR - bildiris ugursuz olsa da sistem islemelidir.
    """
    indi = datetime.now(timezone.utc).isoformat()
    setir = f"[{indi}] {baslik} | {metn}"

    log.critical("BILDIRIS: %s - %s", baslik, metn)
    try:
        with open(BILDIRIS_FAYL, "a", encoding="utf-8") as f:
            f.write(setir + "\n")
        BILDIRIS_METRIKA["gonderilen"] += 1
    except OSError as e:
        BILDIRIS_METRIKA["xeta"] += 1
        log.error("Bildiris fayli yazilmadi: %s", e)

    if not (TELEGRAM_TOKEN and TELEGRAM_CHAT):
        return

    try:
        import httpx
        url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        async with httpx.AsyncClient(timeout=10.0) as c:
            await c.post(url, json={
                "chat_id": TELEGRAM_CHAT,
                "text": f"KRITIK\n\n{baslik}\n{metn}",
            })
        log.info("Telegram bildirisi gonderildi")
    except Exception as e:
        BILDIRIS_METRIKA["xeta"] += 1
        log.error("Telegram bildirisi gonderilmedi: %s", e)
