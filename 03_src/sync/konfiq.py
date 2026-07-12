"""Sync konfiqurasiyasi - .env komponentlerinden DSN qurur."""
import os
from pathlib import Path
from urllib.parse import quote_plus

from dotenv import load_dotenv

KOK = Path(__file__).resolve().parents[2]
load_dotenv(KOK / "01_config" / ".env")


def _dsn(prefiks: str) -> str:
    """
    EDGE_DB_* ve ya MERKEZ_DB_* komponentlerinden DSN qurur.
    Parol varsa elave edilir (URL-kodlanmis).
    """
    host = os.getenv(f"{prefiks}_HOST", "localhost")
    port = os.getenv(f"{prefiks}_PORT", "5432")
    name = os.getenv(f"{prefiks}_NAME")
    user = os.getenv(f"{prefiks}_USER")
    parol = os.getenv(f"{prefiks}_PASSWORD")

    if not name or not user:
        raise RuntimeError(f"{prefiks}_NAME ve {prefiks}_USER .env-de olmalidir")

    if parol:
        # quote_plus: parolda @ : / kimi isareler olsa da DSN pozulmasin
        return f"postgresql://{user}:{quote_plus(parol)}@{host}:{port}/{name}"
    return f"postgresql://{user}@{host}:{port}/{name}"


EDGE_DSN   = _dsn("EDGE_DB")
MERKEZ_DSN = _dsn("MERKEZ_DB")

ZAVOD_KOD = os.getenv("ZAVOD_KOD", "SIYEZEN")

SYNC_INTERVAL     = int(os.getenv("SYNC_INTERVAL", "10"))
SYNC_BATCH_OLCME  = int(os.getenv("SYNC_BATCH_OLCME", "500"))
SYNC_BATCH_ALERT  = int(os.getenv("SYNC_BATCH_ALERT", "100"))
SYNC_ALERT_TEKRAR = int(os.getenv("SYNC_ALERT_TEKRAR", "60"))

VERSIYA = "1.0.0"
