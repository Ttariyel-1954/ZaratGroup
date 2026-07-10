"""
Konkret sensorlar — her biri BazaSensor-dan miras alir.
Fayl: 03_src/sensorlar/sensorlar.py
Cihaz kodlari ve heddler Ders 2-deki seed melumatina uygun.
"""
from baza import BazaSensor


class TemperaturSensor(BazaSensor):
    """S001 — Silo temperaturu (~24 C, yavas suruşur)."""
    def __init__(self, cihaz_kod="S001"):
        super().__init__(
            cihaz_kod=cihaz_kod,
            baza=24.0,
            kuy=0.4,
            drift_amp=3.0, drift_period_s=1800,   # yarim saatliq dalga
            anomaliya_ehtimal=0.01, anomaliya_guc=8.0,
            min_deyer=-5, max_deyer=45,
        )


class RutubetSensor(BazaSensor):
    """S002 — Qarisdirici rutubeti (~13 %)."""
    def __init__(self, cihaz_kod="S002"):
        super().__init__(
            cihaz_kod=cihaz_kod,
            baza=13.0,
            kuy=0.3,
            drift_amp=1.5, drift_period_s=2400,
            anomaliya_ehtimal=0.008, anomaliya_guc=5.0,
            min_deyer=0, max_deyer=30,
        )


class CekiSensor(BazaSensor):
    """S003 — Dozator cekisi (dovri: doldur-boşalt)."""
    def __init__(self, cihaz_kod="S003"):
        super().__init__(
            cihaz_kod=cihaz_kod,
            baza=250.0,
            kuy=3.0,
            dovri_amp=180.0, dovri_period_s=45,   # 45 saniyede bir dovr
            anomaliya_ehtimal=0.005, anomaliya_guc=60.0,
            min_deyer=0, max_deyer=520,
        )


class VibrasiyaSensor(BazaSensor):
    """S004 — Muherrik vibrasiyasi (~2 mm/s, bezen puskurur)."""
    def __init__(self, cihaz_kod="S004"):
        super().__init__(
            cihaz_kod=cihaz_kod,
            baza=2.0,
            kuy=0.3,
            anomaliya_ehtimal=0.02, anomaliya_guc=6.0,
            min_deyer=0, max_deyer=15,
        )


class EnerjiSensor(BazaSensor):
    """S005 — Xett enerji serfiyyati (~37 kW, dovri yuk)."""
    def __init__(self, cihaz_kod="S005"):
        super().__init__(
            cihaz_kod=cihaz_kod,
            baza=37.0,
            kuy=1.1,
            dovri_amp=8.0, dovri_period_s=90,
            anomaliya_ehtimal=0.006, anomaliya_guc=15.0,
            min_deyer=0, max_deyer=65,
        )


# Butun sensorlari bir yerde qeydiyyatdan kecirek
def butun_sensorlar():
    """5 sensordan ibaret siyahi qaytarir."""
    return [
        TemperaturSensor(),
        RutubetSensor(),
        CekiSensor(),
        VibrasiyaSensor(),
        EnerjiSensor(),
    ]
