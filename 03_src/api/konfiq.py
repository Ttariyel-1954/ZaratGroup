"""Konfiqurasiya — .env-dən oxunan yeganə mənbə."""
import os
from pathlib import Path
from dotenv import load_dotenv

KOK = Path(__file__).resolve().parents[2]
load_dotenv(KOK / "01_config" / ".env")

EDGE_DSN = (
    f"host={os.getenv('EDGE_DB_HOST', 'localhost')} "
    f"port={os.getenv('EDGE_DB_PORT', '5434')} "
    f"dbname={os.getenv('EDGE_DB_NAME', 'zavod_edge_db')} "
    f"user={os.getenv('EDGE_DB_USER', 'royatalibova')}"
)

MQTT_HOST  = os.getenv("MQTT_HOST", "localhost")
MQTT_PORT  = int(os.getenv("MQTT_PORT", "1883"))
TOPIC_BASE = os.getenv("MQTT_TOPIC_BASE", "zavod/siyezen")

VERSIYA  = "1.0.0"
API_PORT = int(os.getenv("API_PORT", "8000"))
