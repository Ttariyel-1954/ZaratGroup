#!/usr/bin/env python3
"""Zarat Faza 2 — MQTT → PostgreSQL körpüsü (SUBSCRIBER)"""
import os, json, signal, sys
from datetime import datetime
from pathlib import Path

import psycopg
from dotenv import load_dotenv
import paho.mqtt.client as mqtt

KOK = Path(__file__).resolve().parents[2]
load_dotenv(KOK / "01_config" / ".env")

MQTT_HOST  = os.getenv("MQTT_HOST", "localhost")
MQTT_PORT  = int(os.getenv("MQTT_PORT", "1883"))
TOPIC_BASE = os.getenv("MQTT_TOPIC_BASE", "zavod/siyezen")

EDGE_DSN = (
    f"host={os.getenv('EDGE_DB_HOST')} "
    f"port={os.getenv('EDGE_DB_PORT')} "
    f"dbname={os.getenv('EDGE_DB_NAME')} "
    f"user={os.getenv('EDGE_DB_USER')}"
)

CLIENT_ID = "zarat-kopru"
TOPIC_SUB = f"{TOPIC_BASE}/+/olcme"

SQL_OLCME = """
    INSERT INTO olcme (cihaz_kod, olcme_vaxti, qiymet, keyfiyyet)
    VALUES (%s, %s, %s, %s)
"""
SQL_XEBER = """
    INSERT INTO xeberdarliq (cihaz_kod, olcme_vaxti, qiymet, novu, mesaj)
    VALUES (%s, %s, %s, %s, %s)
"""

conn = None
hedler = {}
sayqac = {"ok": 0, "xeta": 0, "alert": 0}


def hedleri_yukle():
    sql = """
        SELECT c.kod, t.min_hedd, t.max_hedd, t.vahid
        FROM cihaz c JOIN sensor_tipi t ON c.sensor_tipi_kod = t.kod
    """
    with conn.cursor() as cur:
        cur.execute(sql)
        for kod, mn, mx, vahid in cur.fetchall():
            hedler[kod] = (float(mn), float(mx), vahid)
    print(f"[KÖRPÜ] {len(hedler)} cihazın həddi yükləndi.")


def on_connect(client, userdata, flags, reason_code, properties):
    if reason_code == 0:
        print(f"[MQTT] Qoşuldu. Abunə: {TOPIC_SUB}")
        client.subscribe(TOPIC_SUB, qos=1)
    else:
        print(f"[MQTT] Qoşulma xətası: {reason_code}")


def on_message(client, userdata, msg):
    global conn
    try:
        data = json.loads(msg.payload.decode("utf-8"))
        kod  = data["cihaz_kod"]
        qiy  = float(data["qiymet"])
        vaxt = datetime.fromisoformat(data["olcme_vaxti"])

        if kod not in hedler:
            print(f"[XƏBƏRDARLIQ] Naməlum cihaz: {kod} — atıldı")
            sayqac["xeta"] += 1
            return

        mn, mx, vahid = hedler[kod]
        keyfiyyet = 1 if mn <= qiy <= mx else 0

        with conn.cursor() as cur:
            cur.execute(SQL_OLCME, (kod, vaxt, qiy, keyfiyyet))
            if qiy > mx:
                cur.execute(SQL_XEBER, (kod, vaxt, qiy, "yuxari_hedd",
                    f"{kod}: {qiy} {vahid} > maks {mx} {vahid}"))
                sayqac["alert"] += 1
                print(f"  ⚠ ALERT {kod}: {qiy} {vahid} (maks {mx})")
            elif qiy < mn:
                cur.execute(SQL_XEBER, (kod, vaxt, qiy, "asagi_hedd",
                    f"{kod}: {qiy} {vahid} < min {mn} {vahid}"))
                sayqac["alert"] += 1
                print(f"  ⚠ ALERT {kod}: {qiy} {vahid} (min {mn})")

        conn.commit()
        sayqac["ok"] += 1
        print(f"  ✓ {kod:6} {qiy:9.3f} {vahid}   "
              f"[ok={sayqac['ok']} alert={sayqac['alert']} xeta={sayqac['xeta']}]")

    except (KeyError, ValueError, json.JSONDecodeError) as e:
        print(f"[XƏTA] Pozuq mesaj ({msg.topic}): {e}")
        sayqac["xeta"] += 1

    except psycopg.Error as e:
        print(f"[BAZA XƏTASI] {e}")
        sayqac["xeta"] += 1
        try:
            conn.rollback()
        except Exception:
            print("[BAZA] Bağlantı bərpa edilir...")
            conn = psycopg.connect(EDGE_DSN)


def dayandir(signum, frame):
    print(f"\n[KÖRPÜ] Dayandırılır. Yekun: {sayqac}")
    sys.exit(0)

signal.signal(signal.SIGINT, dayandir)


def main():
    global conn
    conn = psycopg.connect(EDGE_DSN)
    print(f"[BAZA] Qoşuldu: {os.getenv('EDGE_DB_NAME')}")
    hedleri_yukle()

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                         client_id=CLIENT_ID,
                         clean_session=False)
    client.on_connect = on_connect
    client.on_message = on_message
    client.reconnect_delay_set(min_delay=1, max_delay=30)

    client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_forever()


if __name__ == "__main__":
    main()
