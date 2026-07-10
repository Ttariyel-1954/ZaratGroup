# Zarat ERP — Faza 2: Zavod Rəqəmsallaşdırılması

## Məqsəd
Siyəzən yem fabrikinin fiziki proseslərindən (temperatur, rütubət,
çəki, vibrasiya, enerji) real-vaxt məlumat toplamaq; MQTT və FastAPI
ilə emal edib lokal bazada (zavod_edge_db) saxlamaq; sonra mərkəzi
Zarat ERP-yə (zarat_erp_2) sinxronlaşdırmaq.

## Memarlıq
Sensor (süni) -> MQTT Broker (Mosquitto) -> FastAPI (validasiya)
  -> zavod_edge_db (PostgreSQL@18, 5434) -> Sync -> zarat_erp_2 (5432)
  -> R Shiny Dashboard

## Mühit
- PostgreSQL@18 (Homebrew, Apple Silicon)
- Python 3.14 · virtual mühit: 00_env/
- Mosquitto (MQTT broker)
- Asılılıqlar: requirements.txt

## İşə başlamaq
    cd ~/Desktop/Zarat_Faza2_Zavod
    source 00_env/bin/activate

## Qovluq strukturu
- 00_env/       — Python virtual mühit
- 01_config/    — konfiqurasiya (.env, mosquitto.conf, topics.md)
- 02_db/        — baza DDL-ləri (edge / merkez)
- 03_src/       — Python kodu (sensorlar, toplama, alert, sync)
- 04_dashboard/ — R Shiny paneli
- 05_servisler/ — launchd/systemd
- 06_test/      — testlər
- _KURS/        — HTML dərslər (1-10)
- _LOG/         — icra qeydləri

## Status
- [x] Dərs 1 — Layihə strukturu və mühitin qurulması
- [ ] Dərs 2 — Edge baza sxemi
- [ ] Dərs 3 — Sensor simulyatoru
- [ ] Dərs 4 — MQTT broker qurulumu
- [ ] Dərs 5 — FastAPI toplama xidməti
- [ ] Dərs 6 — Anomaliya aşkarlama və xəbərdarlıq
- [ ] Dərs 7 — Mərkəzi sinxronizasiya
- [ ] Dərs 8 — Offline dayanıqlılıq
- [ ] Dərs 9 — Canlı monitorinq paneli
- [ ] Dərs 10 — Təhlükəsizlik və yerləşdirmə

## Qeyd
Kafka və çoxagentli (Inventory/Production/Finance) memarlıq şüurlu
şəkildə Faza 3-ə saxlanılıb. Bütün DB adları, portlar və struktur
bu sənəddə kanonikdir.