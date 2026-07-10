"""
zavod_edge_db qosulma komekcisi.
Fayl: 03_src/toplama/db_komekci.py
"""
import os
from dotenv import load_dotenv

_KONF = os.path.join(os.path.dirname(__file__), "..", "..", "01_config", ".env")
load_dotenv(_KONF)


def edge_dsn() -> str:
    """zavod_edge_db ucun qosulma setri (DSN) qaytarir."""
    return (
        f"host={os.getenv('EDGE_DB_HOST', 'localhost')} "
        f"port={os.getenv('EDGE_DB_PORT', '5434')} "
        f"dbname={os.getenv('EDGE_DB_NAME', 'zavod_edge_db')} "
        f"user={os.getenv('EDGE_DB_USER', 'royatalibova')}"
    )
