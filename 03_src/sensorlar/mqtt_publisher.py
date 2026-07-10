"""
Simulyator -> MQTT broker publisher.
Fayl: 03_src/sensorlar/mqtt_publisher.py
"""
import os
import sys
import json
import time
import paho.mqtt.client as mqtt
from paho.mqtt.enums import CallbackAPIVersion

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "toplama"))

from sensorlar import butun_sensorlar
from mqtt_komekci import MQTT_HOST, MQTT_PORT, cihaz_topic


def on_connect(client, userdata, flags, reason_code, properties):
    if reason_code == 0:
        print(f"Broker-e qosuldu: {MQTT_HOST}:{MQTT_PORT}")
    else:
        print(f"Qosulma alinmadi, kod={reason_code}")


def main():
    client = mqtt.Client(
        callback_api_version=CallbackAPIVersion.VERSION2,
        client_id="zarat-publisher",
    )
    client.on_connect = on_connect
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_start()

    sensorlar = butun_sensorlar()
    print("Publisher basladi. CTRL+C ile dayandirin.\n")

    try:
        while True:
            for s in sensorlar:
                o = s.oxu()
                topic = cihaz_topic(o.cihaz_kod)
                payload = json.dumps(o.dict())
                client.publish(topic, payload, qos=0)
                print(f"-> {topic}  {payload}")
            print("-" * 60)
            time.sleep(2)
    except KeyboardInterrupt:
        print("\nPublisher dayandirilir...")
        client.loop_stop()
        client.disconnect()
        print("Bitdi.")


if __name__ == "__main__":
    main()
