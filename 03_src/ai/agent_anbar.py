"""
Agent 2: ANBAR_MUQAYISE — Qaiməni anbar qalığı ilə müqayisə edir.

Məntiq:
  - Riyaziyyat SQL-də edilir (LLM buna toxunmur)
  - LLM yalnız izahat mətni yazır

Kontekstdə gözlənilir (giris.kontekst):
  {
    "sened_netice":    {...},   # OCR_QAIME çıxarışı
    "anbar_qaliq":     [{kod, ad, qaliq, vahid, min_qaliq}],
    "uygunlasma":      [{material_ad, tapildi, material_kod, ferq}]
  }
"""
from __future__ import annotations

import asyncio
import json

from .base import AgentCixisi, AgentGirisi, BaseAgent

SISTEM = """
Sən Azərbaycan yem zavodunun anbar analitikisən.
Sənə qaiməni anbar qalığı ilə müqayisə nəticəsi veriləcək.
Sadə, konkret Azərbaycan dilindəki xülasə yaz (max 5 cümlə).
Potensial problemi — çatışmazlığı, uyğunsuzluğu vurğula.
Cavabın YALNIZ JSON olsun:
{
  "xulase": "...",
  "qeyri_uygun_say": number,
  "kritik_catismazliq": ["material_ad", ...]
}
""".strip()


class ANBAR_MUQAYISE(BaseAgent):
    """Qaiməni anbar qalığı ilə müqayisə edən agent."""

    AGENT_KOD = "ANBAR_MUQAYISE"

    async def icra(self, giris: AgentGirisi) -> AgentCixisi:
        ctx = giris.kontekst

        if not ctx.get("uygunlasma"):
            return AgentCixisi(
                agent_kod=self.AGENT_KOD, model="",
                netice={"xulase": "Kontekst verilmədi"},
                eminlik={}, ugurlu=False,
                xeta="uygunlasma konteksti tapılmadı",
            )

        # Riyaziyyat artıq SQL-də edilib, yalnız izahat lazımdır
        prompt_metn = (
            f"Qaimə nəticəsi:\n"
            f"```json\n{json.dumps(ctx.get('sened_netice', {}), ensure_ascii=False)}\n```\n\n"
            f"Anbar uyğunlaşması:\n"
            f"```json\n{json.dumps(ctx['uygunlasma'], ensure_ascii=False, indent=2)}\n```\n\n"
            f"Xülasə yaz."
        )

        mesajlar = [{"role": "user", "content": prompt_metn}]

        try:
            cavab, g, c, ms = await asyncio.to_thread(
                self._mesaj_gonder, SISTEM, mesajlar
            )
        except Exception as e:
            return AgentCixisi(
                agent_kod=self.AGENT_KOD, model="",
                netice={}, eminlik={},
                ugurlu=False, xeta=str(e)[:500],
            )

        netice = {}
        cavab = cavab.strip()
        if cavab.startswith("{"):
            try:
                netice = json.loads(cavab)
            except json.JSONDecodeError:
                netice = {"xulase": cavab}
        else:
            netice = {"xulase": cavab}

        return AgentCixisi(
            agent_kod   = self.AGENT_KOD,
            model       = "claude-opus-4-6",
            netice      = netice,
            eminlik     = {"xulase": 0.85},
            giris_token = g,
            cixis_token = c,
            muddet_ms   = ms,
            ugurlu      = True,
        )
