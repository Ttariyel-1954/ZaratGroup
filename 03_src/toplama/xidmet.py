"""
FastAPI toplama xidmeti - MQTT dinleyir, validasiya edir, bazaya yazir,
anomaliyalari askarlayir (Ders 6).
Fayl: 03_src/toplama/xidmet.py
Ishe salmaq:
  PYTHONPATH=.:../alert uvicorn xidmet:app --host 0.0.0.0 --port 8020
"""
import os
import sys
import json
import logging
from contextlib import asynccontextmanager

import psycopg
import paho.mqtt.client as mqtt
from paho.mqtt.enums import CallbackAPIVersion
from fastapi import FastAPI
from pydantic import ValidationError

# alert qovlugunu yola elave et
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "alert"))

from db_komekci import edge_dsn
from validasiya import OlcmeMesaj
from mqtt_komekci import MQTT_HOST, MQTT_PORT, TOPIC_BASE
import anomaliya

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s  %(levelname)s  %(message)s")
log = logging.getLogger("toplama")

stat = {"qebul": 0, "yazildi": 0, "redd": 0, "xeberdarliq": 0}

_db = None


def db_qosul():
    global _db
    if _db is None or _db.closed:
        _db = psycopg.connect(edge_dsn(), autocommit=True)
    return _db


def olcme_yaz(m: OlcmeMesaj):
    conn = db_qosul()
    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO olcme (cihaz_kod, olcme_vaxti, qiymet)
               VALUES (%s, %s, %s)""",
            (m.cihaz_kod, m.olcme_vaxti, m.qiymet),
        )
    # --- ANOMALIYA YOXLAMASI (Ders 6) ---
    netice = anomaliya.yoxla(m.cihaz_kod, m.qiymet)
    if netice is not None:
        novu, mesaj = netice
        anomaliya.xeberdarliq_yaz(conn, m.cihaz_kod, m.olcme_vaxti,
                                  m.qiymet, novu, mesaj)
        stat["xeberdarliq"] += 1
        log.warning(f"ALARM [{novu}] {mesaj}")


def on_connect(client, userdata, flags, reason_code, properties):
    if reason_code == 0:
        topic = f"{TOPIC_BASE}/#"
        client.subscribe(topic, qos=0)
        log.info(f"Broker-e qosuldu, abune: {topic}")
    else:
        log.error(f"Broker qosulmasi alinmadi: {reason_code}")


def on_message(client, userdata, msg):
    stat["qebul"] += 1
    try:
        data = json.loads(msg.payload.decode())
        m = OlcmeMesaj(**data)
        olcme_yaz(m)
        stat["yazildi"] += 1
    except (ValidationError, ValueError) as e:
        stat["redd"] += 1
        log.warning(f"REDD ({msg.topic}): {e}")
    except Exception as e:
        stat["redd"] += 1
        log.error(f"XETA ({msg.topic}): {e}")


mqtt_client = mqtt.Client(
    callback_api_version=CallbackAPIVersion.VERSION2,
    client_id="zarat-toplama",
)
mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message


@asynccontextmanager
async def lifespan(app: FastAPI):
    # baslanic: heddleri yukle, broker-e qosul
    conn = db_qosul()
    anomaliya.heddleri_yukle(conn)
    mqtt_client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    mqtt_client.loop_start()
    log.info("Toplama xidmeti basladi (anomaliya aktiv).")
    yield
    mqtt_client.loop_stop()
    mqtt_client.disconnect()
    log.info("Toplama xidmeti dayandi.")


app = FastAPI(title="Zarat Faza 2 - Toplama Xidmeti", lifespan=lifespan)


@app.get("/")
def kok():
    return {"xidmet": "Zarat toplama", "veziyyet": "isleyir"}


@app.get("/saglamliq")
def saglamliq():
    return {"status": "ok", "statistika": stat}


@app.get("/statistika")
def statistika():
    return stat


@app.get("/xeberdarliqlar")
def xeberdarliqlar():
    """Son 20 xeberdarligi qaytarir."""
    conn = db_qosul()
    with conn.cursor() as cur:
        cur.execute("""
            SELECT cihaz_kod, novu, mesaj, olcme_vaxti
            FROM xeberdarliq
            ORDER BY yaradilma DESC LIMIT 20
        """)
        setirler = cur.fetchall()
    return [
        {"cihaz": r[0], "novu": r[1], "mesaj": r[2], "vaxt": str(r[3])}
        for r in setirler
    ]
