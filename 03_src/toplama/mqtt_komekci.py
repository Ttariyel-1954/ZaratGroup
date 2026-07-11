"""
Ortaq MQTT komekcisi — .env-den ayarlari oxuyur.
Fayl: 03_src/toplama/mqtt_komekci.py
paho-mqtt 2.x VERSION2 callback API istifade olunur.
"""
import os
from dotenv import load_dotenv

# .env faylini oxu (layihe koku)
_KONF = os.path.join(os.path.dirname(__file__), "..", "..", "01_config", ".env")
load_dotenv(_KONF)

MQTT_HOST = os.getenv("MQTT_HOST", "localhost")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
TOPIC_BASE = os.getenv("MQTT_TOPIC_BASE", "zavod/siyezen")

# sensor tipi kodu -> topic sozu
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
