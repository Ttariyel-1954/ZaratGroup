"""
Gelen sensor mesajinin validasiyasi (Pydantic v2).
Fayl: 03_src/toplama/validasiya.py
"""
from pydantic import BaseModel, field_validator


class OlcmeMesaj(BaseModel):
    """MQTT-den gelen bir olcme mesaji."""
    cihaz_kod: str
    olcme_vaxti: str
    qiymet: float

    @field_validator("cihaz_kod")
    @classmethod
    def cihaz_kod_bos_olmasin(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("cihaz_kod bos ola bilmez")
        return v.strip()

    @field_validator("qiymet")
    @classmethod
    def qiymet_fiziki_aralig(cls, v: float) -> float:
        # cox geni fiziki  yalniz tamamile menasiz deyerleri redd etserhed 
        # deqiq hedd-asma xeberdarligi Ders 6-dadir
        if v < -1000 or v > 100000:
            raise ValueError(f"qiymet fiziki araligdan kenardir: {v}")
        return v
