#!/usr/bin/env python3
"""Zarat Faza 2 — Sensor simulyatoru (PUBLISHER)"""
import os, sys, json, time, random, signal
from datetime import datetime, timezone
from pathlib import Path

import psycopg
from dotenv import load_dotenv
import paho.mqtt.client as mqtt

KOK = Path(__file__).resolve().parents[2]
load_dotenv(KOK / "01_config" / ".env")

MQTT_HOST  = os.getenv("MQTT_HOST", "localhost")
MQTT_PORT  = int(os.getenv("MQTT_PORT", "1883"))
TOPIC_BASE = os.getenv("MQTT_TOPIC_BASE", "zavod/siyezen")
INTERVAL   = float(os.getenv("SIM_INTERVAL", "5"))

EDGE_DSN = (
    f"host={os.getenv('EDGE_DB_HOST')} "
    f"port={os.getenv('EDGE_DB_PORT')} "
    f"dbname={os.getenv('EDGE_DB_NAME')} "
    f"user={os.getenv('EDGE_DB_USER')}"
)

CLIENT_ID = "zarat-simulyator"
isleyir = True


def cihazlari_oxu():
    sql = """
        SELECT c.kod, t.kod AS tip, t.min_hedd, t.max_hedd, t.vahid
        FROM cihaz c
        JOIN sensor_tipi t ON c.sensor_tipi_kod = t.kod
        WHERE c.status = 'aktiv'
        ORDER BY c.kod
    """
    with psycopg.connect(EDGE_DSN) as conn, conn.cursor() as cur:
        cur.execute(sql)
        setirler = cur.fetchall()

    cihazlar = []
    for kod, tip, mn, mx, vahid in setirler:
        mn, mx = float(mn), float(mx)
        cihazlar.append({
            "kod": kod, "tip": tip, "min": mn, "max": mx, "vahid": vahid,
            "cari": (mn + mx) / 2,
            "addim": (mx - mn) * 0.02,
        })
    return cihazlar


def novbeti_qiymet(c):
    delta = random.uniform(-c["addim"], c["addim"])
    yeni = c["cari"] + delta
    if random.random() < 0.02:
        yeni = c["max"] * random.uniform(1.05, 1.20)
    genislik = c["max"] - c["min"]
    asagi  = c["min"] - genislik * 0.3
    yuxari = c["max"] + genislik * 0.3
    c["cari"] = max(asagi, min(yuxari, yeni))
    return round(c["cari"], 3)


def on_connect(client, userdata, flags, reason_code, properties):
    if reason_code == 0:
        print(f"[MQTT] Qoşuldu: {MQTT_HOST}:{MQTT_PORT}")
        client.publish(f"{TOPIC_BASE}/simulyator/status",
                       "online", qos=1, retain=True)
    else:
        print(f"[MQTT] XƏTA — qoşulma alınmadı: {reason_code}")


def on_disconnect(client, userdata, flags, reason_code, properties):
    if reason_code != 0:
        print(f"[MQTT] Gözlənilməz kəsilmə ({reason_code}) — yenidən qoşulur...")


def dayandir(signum, frame):
    global isleyir
    print("\n[SİM] Dayandırılır...")
    isleyir = False

signal.signal(signal.SIGINT, dayandir)


def main():
    cihazlar = cihazlari_oxu()
    if not cihazlar:
        print("[XƏTA] Bazada aktiv cihaz yoxdur.")
        sys.exit(1)
    print(f"[SİM] {len(cihazlar)} aktiv cihaz: "
          + ", ".join(c["kod"] for c in cihazlar))

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                         client_id=CLIENT_ID)
    client.on_connect    = on_connect
    client.on_disconnect = on_disconnect

    client.will_set(f"{TOPIC_BASE}/simulyator/status",
                    payload="offline", qos=1, retain=True)
    client.reconnect_delay_set(min_delay=1, max_delay=30)

    client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
    client.loop_start()

    sayqac = 0
    while isleyir:
        indi = datetime.now(timezone.utc).isoformat()
        for c in cihazlar:
            qiymet = novbeti_qiymet(c)
            topic  = f"{TOPIC_BASE}/{c['kod']}/olcme"
            payload = json.dumps({
                "cihaz_kod":   c["kod"],
                "qiymet":      qiymet,
                "olcme_vaxti": indi,
                "vahid":       c["vahid"],
            })
            netice = client.publish(topic, payload, qos=1, retain=True)
            if netice.rc != mqtt.MQTT_ERR_SUCCESS:
                print(f"[XƏTA] Göndərilmədi: {topic} (rc={netice.rc})")
            else:
                sayqac += 1
                print(f"  → {c['kod']:6} {qiymet:9.3f} {c['vahid']}")
        print(f"[SİM] Cəmi göndərilib: {sayqac}\n")
        time.sleep(INTERVAL)

    client.publish(f"{TOPIC_BASE}/simulyator/status",
                   "offline", qos=1, retain=True)
    time.sleep(0.5)
    client.loop_stop()
    client.disconnect()
    print(f"[SİM] Bitdi. Ümumi: {sayqac} mesaj.")


if __name__ == "__main__":
    main()
