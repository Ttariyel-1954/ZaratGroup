# Zarat Faza 2 — MQTT Topic Sxemi

Baza yol: zavod/siyezen

## Sensor topic-leri

| Cihaz | Sensor      | Topic                             |
|-------|-------------|-----------------------------------|
| S001  | Temperatur  | zavod/siyezen/temperatur/S001     |
| S002  | Rutubet     | zavod/siyezen/rutubet/S002        |
| S003  | Ceki        | zavod/siyezen/ceki/S003           |
| S004  | Vibrasiya   | zavod/siyezen/vibrasiya/S004      |
| S005  | Enerji      | zavod/siyezen/enerji/S005         |

## Wildcard-lar (abune ucun)

- zavod/siyezen/#              -> butun sensorlar
- zavod/siyezen/temperatur/+   -> yalniz temperaturlar
- zavod/siyezen/+/S001         -> yalniz S001 cihazi

## Mesaj formati (JSON)

{
  "cihaz_kod": "S001",
  "olcme_vaxti": "2026-07-09T18:30:12+00:00",
  "qiymet": 24.19
}

## QoS

- Sensor olcmeleri: QoS 0 (itse problem deyil, davamli axir)
- Xeberdarliqlar (ders 6): QoS 1 (mutleq catmalidir)
