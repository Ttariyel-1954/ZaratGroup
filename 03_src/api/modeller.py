"""Pydantic modelləri — sistemə girən/çıxan datanın rəsmi tərifi."""
from datetime import datetime, timezone, timedelta
from typing import Optional, Literal

from pydantic import BaseModel, Field, field_validator, ConfigDict


class OlcmeIn(BaseModel):
    """Sensordan gələn bir ölçmə. Hər sahə ciddi yoxlanılır."""

    model_config = ConfigDict(
        extra="forbid",
        str_strip_whitespace=True,
    )

    cihaz_kod: str = Field(
        ..., min_length=2, max_length=20,
        pattern=r"^[A-Z0-9_-]+$",
        description="Cihaz kodu, məs. S001",
        examples=["S001"],
    )
    qiymet: float = Field(
        ..., ge=-10_000, le=100_000,
        description="Ölçülən dəyər",
        examples=[24.317],
    )
    olcme_vaxti: datetime = Field(
        ...,
        description="ISO 8601, zaman zonası MƏCBURİ",
        examples=["2026-07-12T09:15:00+04:00"],
    )
    vahid: Optional[str] = Field(None, max_length=15)

    @field_validator("olcme_vaxti")
    @classmethod
    def zona_mecburidir(cls, v: datetime) -> datetime:
        if v.tzinfo is None:
            raise ValueError(
                "olcme_vaxti zaman zonası ilə olmalıdır "
                "(məs. 2026-07-12T09:15:00+04:00)"
            )
        return v

    @field_validator("olcme_vaxti")
    @classmethod
    def gelecek_deyil(cls, v: datetime) -> datetime:
        indi = datetime.now(timezone.utc)
        if v > indi + timedelta(minutes=5):
            raise ValueError(f"olcme_vaxti gələcəkdədir: {v.isoformat()}")
        return v

    @field_validator("olcme_vaxti")
    @classmethod
    def cox_kohne_deyil(cls, v: datetime) -> datetime:
        indi = datetime.now(timezone.utc)
        if v < indi - timedelta(days=7):
            raise ValueError(f"olcme_vaxti 7 gündən köhnədir: {v.isoformat()}")
        return v


class OlcmeOut(BaseModel):
    cihaz_kod: str
    olcme_vaxti: datetime
    qiymet: float
    keyfiyyet: int
    sync_status: int


class CihazOut(BaseModel):
    kod: str
    ad: str
    tip: str
    vahid: str
    min_hedd: float
    max_hedd: float
    status: str


class QebulCavabi(BaseModel):
    status: Literal["qebul", "anomal"]
    cihaz_kod: str
    qiymet: float
    keyfiyyet: int
    xeberdarliq: Optional[str] = None


class SaglamliqCavabi(BaseModel):
    status: str
    baza: str
    cihaz_sayi: int
    versiya: str
