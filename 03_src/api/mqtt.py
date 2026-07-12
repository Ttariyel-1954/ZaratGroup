"""
MQTT qatı — brokerdən mesaj alır, növbəyə qoyur.
paho SİNXRON sapda işləyir; asyncio.Queue ilə async dünyaya körpü qururuq.
"""
import asyncio
import json
import logging

import paho.mqtt.client as mqtt
from pydantic import ValidationError

from .konfiq import MQTT_HOST, MQTT_PORT, TOPIC_BASE
from .modeller import OlcmeIn

log = logging.getLogger("zarat.mqtt")

CLIENT_ID = "zarat-api"
TOPIC_SUB = f"{TOPIC_BASE}/+/olcme"
NOVBE_LIMIT = 5000

novbe = None
loop = None
client = None

MQTT_METRIKA = {"gelen": 0, "qebul": 0, "redd": 0,
                "novbe_dolu": 0, "qosulub": False}


def on_connect(cl, userdata, flags, reason_code, properties):
    if reason_code == 0:
        MQTT_METRIKA["qosulub"] = True
        cl.subscribe(TOPIC_SUB, qos=1)
        log.info("MQTT qosuldu, abune: %s", TOPIC_SUB)
    else:
        MQTT_METRIKA["qosulub"] = False
        log.error("MQTT qosulma xetasi: %s", reason_code)


def on_disconnect(cl, userdata, flags, reason_code, properties):
    MQTT_METRIKA["qosulub"] = False
    if reason_code != 0:
        log.warning("MQTT kesildi (%s) - yeniden qosulur...", reason_code)


def on_message(cl, userdata, msg):
    """DIQQET: bu funksiya PAHO SAPINDA isleyir - burada 'await' OLMAZ."""
    MQTT_METRIKA["gelen"] += 1

    try:
        xam = json.loads(msg.payload.decode("utf-8"))
        olcme = OlcmeIn.model_validate(xam)

    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        MQTT_METRIKA["redd"] += 1
        log.warning("Pozuq JSON [%s]: %s", msg.topic, e)
        return

    except ValidationError as e:
        MQTT_METRIKA["redd"] += 1
        for xeta in e.errors():
            log.warning("Validasiya xetasi [%s] %s: %s",
                        msg.topic, xeta["loc"], xeta["msg"])
        return

    if loop is None or novbe is None:
        return

    try:
        loop.call_soon_threadsafe(novbe.put_nowait, olcme)
        MQTT_METRIKA["qebul"] += 1
    except asyncio.QueueFull:
        MQTT_METRIKA["novbe_dolu"] += 1
        log.error("NOVBE DOLDU (%d) - mesaj atildi!", NOVBE_LIMIT)


def basla(event_loop):
    """lifespan-dan cagirilir."""
    global novbe, loop, client

    loop = event_loop
    novbe = asyncio.Queue(maxsize=NOVBE_LIMIT)

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                         client_id=CLIENT_ID,
                         clean_session=False)
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message
    client.reconnect_delay_set(min_delay=1, max_delay=30)

    client.will_set(f"{TOPIC_BASE}/api/status",
                    payload="offline", qos=1, retain=True)

    client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_start()

    client.publish(f"{TOPIC_BASE}/api/status", "online", qos=1, retain=True)
    log.info("MQTT basladi: %s:%s", MQTT_HOST, MQTT_PORT)
    return novbe


def dayandir():
    if client is None:
        return
    client.publish(f"{TOPIC_BASE}/api/status", "offline", qos=1, retain=True)
    client.loop_stop()
    client.disconnect()
    log.info("MQTT dayandi.")
