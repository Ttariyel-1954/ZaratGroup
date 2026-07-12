"""Loglama konfiqurasiyası — həm ekrana, həm fayla."""
import logging
import logging.handlers
from pathlib import Path

KOK = Path(__file__).resolve().parents[2]
LOG_QOVLUQ = KOK / "_LOG"
LOG_QOVLUQ.mkdir(exist_ok=True)


def qur(seviyye=logging.INFO):
    format = logging.Formatter(
        "%(asctime)s [%(levelname)-7s] %(name)-14s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    ekran = logging.StreamHandler()
    ekran.setFormatter(format)

    fayl = logging.handlers.RotatingFileHandler(
        LOG_QOVLUQ / "api.log",
        maxBytes=10 * 1024 * 1024,
        backupCount=5,
        encoding="utf-8",
    )
    fayl.setFormatter(format)

    kok = logging.getLogger()
    kok.setLevel(seviyye)
    kok.handlers.clear()
    kok.addHandler(ekran)
    kok.addHandler(fayl)

    logging.getLogger("psycopg.pool").setLevel(logging.WARNING)
