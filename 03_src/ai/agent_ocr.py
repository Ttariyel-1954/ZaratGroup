"""
Agent 1: OCR_QAIME — PDF/şəkil sənəddən strukturlu məlumat çıxarır.

Çıxarılan sahələr:
  - qarsi_teref : təchizatçı adı
  - nomre       : qaimənin nömrəsi
  - tarix       : sənədin tarixi (ISO 8601)
  - setirler    : [{material, miqdar, vahid, vahid_qiymet, cemi}]
  - cemi_mebleg : cəmi məbləğ
  - valyuta     : AZN / USD / EUR / ...

§0 → Bu agent yalnız TƏKLİF edir. İnsan təsdiqləyir.
"""
from __future__ import annotations

import asyncio
import json
import logging

from .base import AgentCixisi, AgentGirisi, BaseAgent, prompt_sha256

log = logging.getLogger("ai.ocr_qaime")

SISTEM = """
Sən Azərbaycan yem zavodunun mühasibat köməkçisisən.
Sənə qaimə (faktura / invoice / накладная) faylı veriləcək.
Faylı diqqətlə oxuyub aşağıdaki JSON-u qaytarmalısan.

Cavabın YALNIZ JSON olmalıdır — başqa heç bir mətn olmadan.
Əgər bir sahə görünmürsə — null yaz.
Rəqəmlərdə vergül (1.234,56) formatı varsa — nöqtəyə (1234.56) çevir.

{
  "qarsi_teref":  "string|null",
  "nomre":        "string|null",
  "tarix":        "YYYY-MM-DD|null",
  "setirler": [
    {
      "material":     "string",
      "miqdar":       number,
      "vahid":        "kq|ton|litr|ədəd|...",
      "vahid_qiymet": number|null,
      "cemi":         number|null
    }
  ],
  "cemi_mebleg":  number|null,
  "valyuta":      "AZN|USD|EUR|...|null",
  "_qeydler":     "string|null"
}
""".strip()

EMINLIK_REHBERI = """
Hər sahə üçün öz əminliyini 0..1 ölçüsündə JSON kimi qaytar.
Yalnız əsas sahələr:
{
  "qarsi_teref": 0.95,
  "nomre":       0.90,
  "tarix":       0.85,
  "setirler":    0.80,
  "cemi_mebleg": 0.75
}
""".strip()


def _json_axtar(metn: str) -> dict:
    """Cavabdan JSON bloку çıxarır. Əgər tapılmasa boş dict qaytarır."""
    metn = metn.strip()
    # Kod bloku varsa soyundur
    if metn.startswith("```"):
        xetler = metn.splitlines()
        metn   = "\n".join(
            x for x in xetler
            if not x.startswith("```")
        ).strip()
    try:
        return json.loads(metn)
    except json.JSONDecodeError:
        # JSON-un başlandığı yeri tap
        bas = metn.find("{")
        son = metn.rfind("}") + 1
        if bas >= 0 and son > bas:
            try:
                return json.loads(metn[bas:son])
            except json.JSONDecodeError:
                pass
    log.warning("JSON parse uğursuz, boş nəticə qaytarılır")
    return {}


class OCR_QAIME(BaseAgent):
    """
    PDF / şəkil qaiməsindən strukturlu məlumat çıxaran agent.
    İki LLM çağırışı: 1) nəticə, 2) əminlik.
    """

    AGENT_KOD = "OCR_QAIME"

    async def icra(self, giris: AgentGirisi) -> AgentCixisi:
        if not giris.melumat:
            return AgentCixisi(
                agent_kod=self.AGENT_KOD, model="",
                netice={}, eminlik={},
                ugurlu=False, xeta="Fayl məlumatı verilmədi",
            )

        # ── 1. Nəticə çağırışı ───────────────────────────────────────────────
        mesajlar = [
            {
                "role": "user",
                "content": [
                    self._fayl_blok(giris.melumat, giris.mime_tipi),
                    {"type": "text", "text": "Bu sənədi strukturlaşdır."},
                ],
            }
        ]

        sha = prompt_sha256(SISTEM, str(giris.sened_id))

        try:
            # _mesaj_gonder sinxrondur → event loop bloklanmasın
            cavab1, g1, c1, ms1 = await asyncio.to_thread(
                self._mesaj_gonder, SISTEM, mesajlar
            )
        except Exception as e:
            return AgentCixisi(
                agent_kod=self.AGENT_KOD, model="",
                netice={}, eminlik={},
                ugurlu=False, xeta=str(e)[:500],
                giris_token=0, cixis_token=0, muddet_ms=0,
                prompt_sha=sha,
            )

        netice = _json_axtar(cavab1)

        # ── 2. Əminlik çağırışı ──────────────────────────────────────────────
        eminlik_mesajlar = [
            {
                "role": "user",
                "content": [
                    self._fayl_blok(giris.melumat, giris.mime_tipi),
                    {
                        "type": "text",
                        "text": (
                            f"Sən bu sənəddən bu nəticəni çıxardın:\n"
                            f"```json\n{json.dumps(netice, ensure_ascii=False, indent=2)}\n```\n"
                            f"İndi hər sahə üçün öz əminliyini (0..1) qaytar."
                        ),
                    },
                ],
            }
        ]

        try:
            cavab2, g2, c2, ms2 = await asyncio.to_thread(
                self._mesaj_gonder, EMINLIK_REHBERI, eminlik_mesajlar
            )
            eminlik = _json_axtar(cavab2)
        except Exception:
            eminlik = {}
            g2 = c2 = ms2 = 0

        return AgentCixisi(
            agent_kod    = self.AGENT_KOD,
            model        = "claude-opus-4-6",
            netice       = netice,
            eminlik      = eminlik,
            giris_token  = g1 + g2,
            cixis_token  = c1 + c2,
            muddet_ms    = ms1 + ms2,
            ugurlu       = True,
            prompt_sha   = sha,
        )
