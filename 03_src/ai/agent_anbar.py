"""
Agent 2: ANBAR_MUQAYISE — SQL tapıntıları üçün LLM izahı yazır.

Dizayn qaydası:
  - Bütün hesablamalar SQL-də edilir (agent_server.py-da)
  - Bu agent YALNIZ izah_yaz() ilə çağırılır
  - LLM rəqəm hesablamır, yalnız operatora sadə dildə izah edir
  - Nəticə zavod_ai.qerar-a yazılır (cixaris-ə YOX)

§0 → Bu agent yalnız TƏKLİF edir. İnsan qərar verir.
"""
from __future__ import annotations

import asyncio
import json
import logging

from .base import AgentGirisi, AgentCixisi, BaseAgent

log = logging.getLogger("ai.anbar_muqayise")

SISTEM = """
Sən Azərbaycan yem zavodunun anbar analitikisən.
Sənə anbar yoxlamasının rəqəmsal nəticəsi veriləcək.
Operatora Azərbaycan dilində, SADƏ VƏ KONKRET izah yaz.
Texniki jarqon, formula, faiz hesabı YOX — adi insan dili.

YALNIZ JSON qaytarmalısan. Markdown çərçivəsi YOX.

{
  "izah":     "Nə olduğunu 2-3 cümlə ilə izah et.",
  "tovsiyye": ["Birinci addım", "İkinci addım"]
}
""".strip()


class ANBAR_MUQAYISE(BaseAgent):
    """SQL tapıntılarını LLM ilə izah edən agent."""

    AGENT_KOD = "ANBAR_MUQAYISE"

    async def izahla(
        self, basliq: str, delil: dict
    ) -> tuple[str, list, int, int, int]:
        """
        Bir tapıntı üçün LLM izahı.
        Returns: (izah, tovsiyye_list, giris_token, cixis_token, muddet_ms)
        """
        prompt = (
            f"Mövzu: {basliq}\n"
            f"Rəqəmlər: {json.dumps(delil, ensure_ascii=False)}\n\n"
            f"Operatora sadə dildə izah et: nə olub, niyə problemdir, nə etməli."
        )
        mesajlar = [{"role": "user", "content": prompt}]

        try:
            cavab, g, c, ms = await asyncio.to_thread(
                self._mesaj_gonder, SISTEM, mesajlar
            )
        except Exception as e:
            log.error("LLM xətası (%s): %s", basliq, e)
            return f"İzah əldə edilə bilmədi: {e}", [], 0, 0, 0

        # Markdown çərçivəsini soy
        cavab = cavab.strip()
        if cavab.startswith("```"):
            cavab = "\n".join(
                x for x in cavab.splitlines()
                if not x.startswith("```")
            ).strip()

        try:
            parsed = json.loads(cavab)
            return (
                parsed.get("izah", cavab),
                parsed.get("tovsiyye", []),
                g, c, ms,
            )
        except json.JSONDecodeError:
            log.warning("JSON parse uğursuz, mətn kimi qaytar")
            return cavab, [], g, c, ms

    async def icra(self, giris: AgentGirisi) -> AgentCixisi:
        """Köhnə interfeys — istifadə edilmir, endpoint birbaşa izahla() çağırır."""
        return AgentCixisi(
            agent_kod=self.AGENT_KOD, model="",
            netice={}, eminlik={}, ugurlu=True,
        )
