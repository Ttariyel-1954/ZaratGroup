"""Eksponensial backoff + jitter."""
import random


class Backoff:
    def __init__(self, bas=1.0, tavan=300.0, emsal=2.0):
        self.bas   = bas
        self.tavan = tavan
        self.emsal = emsal
        self.cari  = bas
        self.ugursuz_say = 0

    def ugursuz(self) -> float:
        """Ugursuzluq: gozleme muddetini artir ve qaytar."""
        self.ugursuz_say += 1
        gozleme = self.cari

        jitter = gozleme * random.uniform(-0.25, 0.25)
        gozleme = max(0.5, gozleme + jitter)

        self.cari = min(self.tavan, self.cari * self.emsal)
        return gozleme

    def ugurlu(self) -> None:
        self.cari = self.bas
        self.ugursuz_say = 0

    @property
    def problemdedir(self) -> bool:
        return self.ugursuz_say > 0
