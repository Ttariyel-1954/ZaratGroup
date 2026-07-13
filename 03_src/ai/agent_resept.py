"""
Agent 3: RESEPT_SERFIYYAT — İstehsal sifarişinin material sərfiyyatını yoxlayır.

Kontekstdə gözlənilir (giris.kontekst):
  {
    "sifaris_id":      int,
    "resept_kod":      str,
    "planlanan_miqdar": float,
    "faktiki_miqdar":  float,
    "sapma": [
      {
        "material_kod":  str,
        "ad":            str,
        "gozlenilen":    float,
        "faktiki":       float,
        "dozum_faiz":    float,
        "faiz_ferq":     float   # neqativ = az işlənib, müsbət = çox
      }
    ],
    "sensor_xeberdarliq": [str]   # Sensor sistemindən gəlmiş xəbərdarlıqlar
  }

§0 → LLM yalnız izahat və tövsiyə verir. Bazaya bir şey YAZMAZ.
"""
from __future__ import annotations

import asyncio
import json

from .base import AgentCixisi, AgentGirisi, BaseAgent

SISTEM = """
Sən Azərbaycan yem zavodunun istehsal analitikisən.
Sənə istehsal sifarişinin resept-faktiki müqayisəsi veriləcək.
Dözmə zonasından kənar olan materialları vurğula.
Sensor xəbərdarlıqları varsa — əlaqəni izah et.

Cavabın YALNIZ JSON olsun:
{
  "xulase":       "...",
  "kritikler": [
    {
      "material": "...",
      "faiz_ferq": 5.3,
      "sebeb_ferziyye": "...",
      "tovsiyye": "..."
    }
  ],
  "umumi_qiymet": "normal|diqqet|kritik"
}
""".strip()


class RESEPT_SERFIYYAT(BaseAgent):
    """Resept-faktiki sərfiyyat fərqini LLM ilə izah edən agent."""

    AGENT_KOD = "RESEPT_SERFIYYAT"

    async def icra(self, giris: AgentGirisi) -> AgentCixisi:
        ctx = giris.kontekst
        if not ctx.get("sapma"):
            return AgentCixisi(
                agent_kod=self.AGENT_KOD, model="",
                netice={"xulase": "Sapma məlumatı verilmədi"},
                eminlik={}, ugurlu=False,
                xeta="sapma konteksti tapılmadı",
            )

        prompt_metn = (
            f"Sifariş ID: {ctx.get('sifaris_id')}\n"
            f"Resept: {ctx.get('resept_kod')}, "
            f"planlanmış={ctx.get('planlanan_miqdar')} kq, "
            f"faktiki={ctx.get('faktiki_miqdar')} kq\n\n"
            f"Sapma cədvəli:\n"
            f"```json\n{json.dumps(ctx['sapma'], ensure_ascii=False, indent=2)}\n```\n"
        )

        if ctx.get("sensor_xeberdarliq"):
            prompt_metn += (
                f"\nSensor sistemi bu xəbərdarlıqları göndərdi:\n"
                + "\n".join(f"  - {x}" for x in ctx["sensor_xeberdarliq"])
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
        bas = cavab.find("{")
        son = cavab.rfind("}") + 1
        if bas >= 0 and son > bas:
            try:
                netice = json.loads(cavab[bas:son])
            except json.JSONDecodeError:
                netice = {"xulase": cavab}
        else:
            netice = {"xulase": cavab}

        return AgentCixisi(
            agent_kod   = self.AGENT_KOD,
            model       = "claude-opus-4-6",
            netice      = netice,
            eminlik     = {"umumi_qiymet": 0.80},
            giris_token = g,
            cixis_token = c,
            muddet_ms   = ms,
            ugurlu      = True,
        )
