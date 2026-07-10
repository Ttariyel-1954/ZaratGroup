"""
Ortaq MQTT  .env-den ayarlari oxuyur.komekcisi 
Fayl: 03_src/toplama/mqtt_komekci.py
"""
import os
from dotenv import load_dotenv

_KONF = os.path.join(os.path.dirname(__file__), "..", "..", "01_config", ".env")
load_dotenv(_KONF)

MQTT_HOST = os.getenv("MQTT_HOST", "localhost")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
TOPIC_BASE = os.getenv("MQTT_TOPIC_BASE", "zavod/siyezen")

TIP_TOPIC = {
    "S001": "temperatur",
    "S002": "rutubet",
    "S003": "ceki",
    "S004": "vibrasiya",
    "S005": "enerji",
}


def cihaz_topic(cihaz_kod: str) -> str:
    """Cihaz kodu ucun tam topic yolu qaytarir."""
    soz = TIP_TOPIC.get(cihaz_kod, "diger")
    return f"{TOPIC_BASE}/{soz}/{cihaz_kod}"
