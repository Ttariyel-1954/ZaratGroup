"""
AI agent bazası — Faza 3.

Hər agent bu ABC-ni implement edir:
  - icra() → AgentCixisi
  - Agent öz nəticəsini ai.cixaris-ə ÖZÜ YAZMİR.
    Agent server (agent_server.py) yazır.

§0 qayda: AI TƏKLİF edir, İNSAN qərar verir.
"""
from __future__ import annotations

import hashlib
import logging
import os
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import anthropic
from dotenv import load_dotenv

KOK = Path(__file__).resolve().parents[2]
load_dotenv(KOK / "01_config" / ".env")

log = logging.getLogger("ai.base")

# ── Anthropic müştərisi ───────────────────────────────────────────────────────
# Yalnız bir dəfə yaradılır (modul səviyyəsindədir).
anthropic_musteri = anthropic.Anthropic(
    api_key=os.getenv("ANTHROPIC_API_KEY", "")
)

MODEL        = os.getenv("AI_MODEL", "claude-opus-4-6")
MAX_TOKEN    = int(os.getenv("AI_MAX_TOKEN", "4096"))


# ── Dataclass-lar ─────────────────────────────────────────────────────────────

@dataclass
class AgentGirisi:
    """Agentə verilən giriş."""
    sened_id:  int
    fayl_id:   int | None
    # Faylın ikili məzmunu (PDF, şəkil) — yükləmə agent serverinin işidir
    melumat:   bytes | None = None
    mime_tipi: str          = "application/pdf"
    # Əlavə kontekst (anbar qalığı, resept, s.)
    kontekst:  dict[str, Any] = field(default_factory=dict)


@dataclass
class AgentCixisi:
    """Agentdən geri qaytarılan nəticə."""
    agent_kod:  str
    model:      str
    netice:     dict[str, Any]        # Çıxarılan strukturlu məlumat
    eminlik:    dict[str, float]       # Sahə üzrə əminlik (0..1)
    # LLM jurnal üçün
    giris_token:  int = 0
    cixis_token:  int = 0
    muddet_ms:    int = 0
    ugurlu:       bool = True
    xeta:         str | None = None
    prompt_sha:   str | None = None    # Keş üçün


# ── Yardımçı: prompt SHA ──────────────────────────────────────────────────────

def prompt_sha256(system: str, *hisseler: str) -> str:
    """Eyni promptun ikinci dəfə göndərilməsini keşlə dayandırmaq üçün."""
    birlesmis = system + "".join(hisseler)
    return hashlib.sha256(birlesmis.encode()).hexdigest()


# ── Base Agent ────────────────────────────────────────────────────────────────

class BaseAgent(ABC):
    """
    Bütün agentlərin əsas sinfi.

    Konkret agent YALNIZ `icra()` metodunu implement edir.
    `cagir()` LLM çağırışını, token sayını, müddəti idarə edir.
    """

    AGENT_KOD: str = "NAMELUM"

    def __init__(self) -> None:
        self._log = logging.getLogger(f"ai.{self.AGENT_KOD.lower()}")

    @abstractmethod
    async def icra(self, giris: AgentGirisi) -> AgentCixisi:
        """
        Agentin əsas məntiqi.
        Faylı oxu, LLM-ə göndər, nəticəni qaytar.
        """
        ...

    def _mesaj_gonder(
        self,
        sistem: str,
        mesajlar: list[dict],
        *,
        model: str = MODEL,
        max_token: int = MAX_TOKEN,
    ) -> tuple[dict, int, int, int]:
        """
        Sinxron Claude API çağırışı.
        Returns: (cavab_metn_dict, giris_token, cixis_token, muddet_ms)

        Agentlər async deyil — agent_server.py to_thread() ilə çağırır.
        """
        bas = time.monotonic()
        cavab = anthropic_musteri.messages.create(
            model=model,
            max_tokens=max_token,
            system=sistem,
            messages=mesajlar,
        )
        muddet_ms  = int((time.monotonic() - bas) * 1000)
        giris_tok  = cavab.usage.input_tokens
        cixis_tok  = cavab.usage.output_tokens
        metn       = cavab.content[0].text if cavab.content else ""

        self._log.info(
            "LLM cavab: giriş=%d, çıxış=%d, müddət=%dms",
            giris_tok, cixis_tok, muddet_ms,
        )
        return metn, giris_tok, cixis_tok, muddet_ms

    def _fayl_blok(self, melumat: bytes, mime: str) -> dict:
        """
        PDF və ya şəkil üçün Anthropic API content bloku.
        """
        import base64
        if mime == "application/pdf":
            return {
                "type": "document",
                "source": {
                    "type": "base64",
                    "media_type": "application/pdf",
                    "data": base64.standard_b64encode(melumat).decode(),
                },
            }
        # Şəkil
        return {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": mime,
                "data": base64.standard_b64encode(melumat).decode(),
            },
        }
