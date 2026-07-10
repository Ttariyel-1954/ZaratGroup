"""
Baza sensor sinfi — butun sensorlarin ortaq davranisi.
Fayl: 03_src/sensorlar/baza.py
"""
import random
import math
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone


@dataclass
class Olcme:
    """Bir sensor oxunusu."""
    cihaz_kod: str
    olcme_vaxti: str        # ISO 8601 format
    qiymet: float

    def dict(self) -> dict:
        return {
            "cihaz_kod": self.cihaz_kod,
            "olcme_vaxti": self.olcme_vaxti,
            "qiymet": round(self.qiymet, 4),
        }


class BazaSensor:
    """
    Butun sensorlarin baza sinfi.
    Realist siqnal 5 elementden yaranir:
    baza + kuy + suruşme (drift) + dovrilik + anomaliya
    """

    def __init__(self, cihaz_kod, baza, kuy=0.0,
                 drift_amp=0.0, drift_period_s=3600,
                 dovri_amp=0.0, dovri_period_s=60,
                 anomaliya_ehtimal=0.0, anomaliya_guc=0.0,
                 min_deyer=None, max_deyer=None):
        self.cihaz_kod = cihaz_kod
        self.baza = baza
        self.kuy = kuy
        self.drift_amp = drift_amp
        self.drift_period_s = drift_period_s
        self.dovri_amp = dovri_amp
        self.dovri_period_s = dovri_period_s
        self.anomaliya_ehtimal = anomaliya_ehtimal
        self.anomaliya_guc = anomaliya_guc
        self.min_deyer = min_deyer
        self.max_deyer = max_deyer
        self._start = time.time()

    def _hesabla(self) -> float:
        t = time.time() - self._start

        # 1) baza deyer
        deyer = self.baza

        # 2) kuy — kicik tesadufi terreddud
        deyer += random.uniform(-self.kuy, self.kuy)

        # 3) suruşme (drift) — yavas, hamar deyisme
        if self.drift_amp:
            deyer += self.drift_amp * math.sin(2 * math.pi * t / self.drift_period_s)

        # 4) dovrilik — tekrarlanan naxis
        if self.dovri_amp:
            deyer += self.dovri_amp * math.sin(2 * math.pi * t / self.dovri_period_s)

        # 5) anomaliya — nadir, keskin sicrayis
        if random.random() < self.anomaliya_ehtimal:
            deyer += random.choice([-1, 1]) * self.anomaliya_guc

        # mumkun hedd mehdudiyyeti (fiziki reallıq)
        if self.min_deyer is not None:
            deyer = max(self.min_deyer, deyer)
        if self.max_deyer is not None:
            deyer = min(self.max_deyer, deyer)

        return deyer

    def oxu(self) -> Olcme:
        """Bir oxunus qaytarir."""
        indi = datetime.now(timezone.utc).isoformat()
        return Olcme(
            cihaz_kod=self.cihaz_kod,
            olcme_vaxti=indi,
            qiymet=self._hesabla(),
        )
