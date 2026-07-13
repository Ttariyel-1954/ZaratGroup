"""
AI Agent Server — port 8100 (mərkəzdə işləyir).

Endpointlər:
  POST /agent/ocr        — PDF/şəkil qaiməsini işlə
  POST /agent/anbar      — Qaimə ↔ anbar müqayisəsi
  POST /agent/resept     — Resept ↔ faktiki sərfiyyat
  GET  /health           — Sağlamlıq
  GET  /metrikalar       — Token xərci statistikası

Hər çağırış:
  1. zavod_ai.jurnal-a yazılır (xərcə nəzarət)
  2. Nəticə zavod_ai.cixaris-ə yazılır (status='teklif')
  3. Panel operatorun qərarını gözləyir

İşə salma:
  cd ~/Desktop/Zarat_Faza2_Zavod
  source 00_env/bin/activate
  python -m uvicorn ai.agent_server:app --port 8100 --host 0.0.0.0
"""
from __future__ import annotations

import asyncio
import base64
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from .agent_anbar import ANBAR_MUQAYISE
from .agent_ocr import OCR_QAIME
from .agent_resept import RESEPT_SERFIYYAT
from .base import AgentCixisi, AgentGirisi

KOK = Path(__file__).resolve().parents[2]
load_dotenv(KOK / "01_config" / ".env")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)-7s] %(name)-12s | %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("ai.server")

# ── Konfiqurasiya ─────────────────────────────────────────────────────────────

def _dsn(pref: str) -> str:
    from urllib.parse import quote_plus
    host  = os.getenv(f"{pref}_HOST", "localhost")
    port  = os.getenv(f"{pref}_PORT", "5432")
    name  = os.getenv(f"{pref}_NAME", "")
    user  = os.getenv(f"{pref}_USER", "")
    parol = os.getenv(f"{pref}_PASSWORD", "")
    if parol:
        return f"postgresql://{user}:{quote_plus(parol)}@{host}:{port}/{name}"
    return f"postgresql://{user}@{host}:{port}/{name}"


MERKEZ_DSN = _dsn("MERKEZ_DB")
AI_GUNLUK_LIMIT = int(os.getenv("AI_GUNLUK_TOKEN_LIMITI", "500000"))

# ── Agentlər ─────────────────────────────────────────────────────────────────

AGENTLER: dict[str, Any] = {
    "OCR_QAIME":       OCR_QAIME(),
    "ANBAR_MUQAYISE":  ANBAR_MUQAYISE(),
    "RESEPT_SERFIYYAT": RESEPT_SERFIYYAT(),
}

METRIKA = {"jurnal_yazilan": 0, "cixaris_yazilan": 0, "xeta": 0,
           "basladi": datetime.now(timezone.utc)}


# ── Verilənlər bazası ─────────────────────────────────────────────────────────

_merkez_conn: psycopg.AsyncConnection | None = None


async def _merkez() -> psycopg.AsyncConnection:
    global _merkez_conn
    if _merkez_conn is None or _merkez_conn.closed:
        _merkez_conn = await psycopg.AsyncConnection.connect(MERKEZ_DSN)
        await _merkez_conn.set_autocommit(True)
    return _merkez_conn


async def _jurnal_yaz(cixis: AgentCixisi, sened_id: int) -> None:
    conn = await _merkez()
    async with conn.cursor() as cur:
        await cur.execute(
            """
            INSERT INTO zavod_ai.jurnal
                (agent_kod, model, sened_id, giris_token, cixis_token,
                 muddet_ms, ugurlu, xeta, prompt_sha)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (cixis.agent_kod, cixis.model, sened_id,
             cixis.giris_token, cixis.cixis_token,
             cixis.muddet_ms, cixis.ugurlu, cixis.xeta,
             cixis.prompt_sha),
        )
    METRIKA["jurnal_yazilan"] += 1


async def _cixaris_yaz(cixis: AgentCixisi, sened_id: int,
                        fayl_id: int | None) -> int:
    """zavod_ai.cixaris-ə yazır, id qaytarır."""
    conn = await _merkez()
    async with conn.cursor() as cur:
        await cur.execute(
            """
            INSERT INTO zavod_ai.cixaris
                (sened_id, fayl_id, agent_kod, model,
                 netice, eminlik, status)
            VALUES (%s, %s, %s, %s, %s::jsonb, %s::jsonb, 'teklif')
            RETURNING id
            """,
            (sened_id, fayl_id, cixis.agent_kod, cixis.model,
             _json_str(cixis.netice), _json_str(cixis.eminlik)),
        )
        return (await cur.fetchone())[0]


async def _gunluk_token_yoxla() -> bool:
    """Bu gün limiti aşıbmı?"""
    try:
        conn = await _merkez()
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT coalesce(sum(giris_token + cixis_token), 0)
                FROM zavod_ai.jurnal
                WHERE vaxt > now() - interval '1 day'
                  AND ugurlu = true
                """,
            )
            cem = (await cur.fetchone())[0]
        return cem < AI_GUNLUK_LIMIT
    except Exception:
        return True  # DB xətasında blok etmə


def _json_str(v: Any) -> str:
    import json
    return json.dumps(v, ensure_ascii=False)


# ── Lifespan ──────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info("AI Server başlayır. Agentlər: %s", list(AGENTLER))
    try:
        conn = await _merkez()
        async with conn.cursor() as cur:
            await cur.execute("SELECT 1")
        log.info("Mərkəz DB bağlantısı: OK")
    except Exception as e:
        log.warning("Mərkəz DB əlçatmazdır: %s", e)
    yield
    if _merkez_conn and not _merkez_conn.closed:
        await _merkez_conn.close()
    log.info("AI Server sondu.")


app = FastAPI(
    title="Zarat AI Agent Server",
    description="OCR, Anbar Müqayisə, Resept Sərfiyyat — Faza 3",
    version="1.0.0",
    lifespan=lifespan,
)


# ── Modellər ──────────────────────────────────────────────────────────────────

class OCR_Sorgu(BaseModel):
    sened_id:  int
    fayl_id:   int
    melumat_b64: str          # base64 fayl məzmunu
    mime_tipi:   str = "application/pdf"


class Kontekst_Sorgu(BaseModel):
    sened_id:  int
    fayl_id:   int | None = None
    kontekst:  dict[str, Any] = {}


# ── Endpointlər ───────────────────────────────────────────────────────────────

@app.get("/health")
async def saglamliq():
    db_ok = False
    try:
        conn = await _merkez()
        async with conn.cursor() as cur:
            await cur.execute("SELECT 1")
        db_ok = True
    except Exception:
        pass
    return {"status": "ok" if db_ok else "db_xetasi",
            "agentler": list(AGENTLER),
            "gunluk_limit": AI_GUNLUK_LIMIT}


@app.get("/metrikalar")
async def metrikalar():
    isleme_san = int(
        (datetime.now(timezone.utc) - METRIKA["basladi"]).total_seconds()
    )
    return {**METRIKA, "isleme_saniye": isleme_san,
            "basladi": METRIKA["basladi"].isoformat()}


@app.post("/agent/ocr", status_code=201)
async def ocr_icra(sorgu: OCR_Sorgu):
    """PDF/şəkil qaiməsini oxuyub strukturlaşdırır."""
    if not await _gunluk_token_yoxla():
        raise HTTPException(status_code=429,
                            detail="Günlük token limiti aşıldı.")

    try:
        melumat = base64.b64decode(sorgu.melumat_b64)
    except Exception:
        raise HTTPException(status_code=400, detail="Yanlış base64 məlumat.")

    giris = AgentGirisi(
        sened_id=sorgu.sened_id,
        fayl_id=sorgu.fayl_id,
        melumat=melumat,
        mime_tipi=sorgu.mime_tipi,
    )

    cixis = await AGENTLER["OCR_QAIME"].icra(giris)

    await _jurnal_yaz(cixis, sorgu.sened_id)
    if not cixis.ugurlu:
        METRIKA["xeta"] += 1
        raise HTTPException(status_code=500, detail=cixis.xeta)

    cixaris_id = await _cixaris_yaz(cixis, sorgu.sened_id, sorgu.fayl_id)
    METRIKA["cixaris_yazilan"] += 1

    return {
        "cixaris_id": cixaris_id,
        "netice":     cixis.netice,
        "eminlik":    cixis.eminlik,
        "token":      cixis.giris_token + cixis.cixis_token,
    }


@app.post("/agent/anbar", status_code=201)
async def anbar_icra(sorgu: Kontekst_Sorgu):
    """Qaiməni anbar qalığı ilə müqayisə edir."""
    if not await _gunluk_token_yoxla():
        raise HTTPException(status_code=429,
                            detail="Günlük token limiti aşıldı.")

    giris = AgentGirisi(
        sened_id=sorgu.sened_id,
        fayl_id=sorgu.fayl_id,
        kontekst=sorgu.kontekst,
    )
    cixis = await AGENTLER["ANBAR_MUQAYISE"].icra(giris)

    await _jurnal_yaz(cixis, sorgu.sened_id)
    if not cixis.ugurlu:
        METRIKA["xeta"] += 1
        raise HTTPException(status_code=500, detail=cixis.xeta)

    cixaris_id = await _cixaris_yaz(cixis, sorgu.sened_id, sorgu.fayl_id)
    METRIKA["cixaris_yazilan"] += 1

    return {"cixaris_id": cixaris_id, "netice": cixis.netice,
            "token": cixis.giris_token + cixis.cixis_token}


@app.post("/agent/resept", status_code=201)
async def resept_icra(sorgu: Kontekst_Sorgu):
    """Resept-faktiki sərfiyyat fərqini izah edir."""
    if not await _gunluk_token_yoxla():
        raise HTTPException(status_code=429,
                            detail="Günlük token limiti aşıldı.")

    giris = AgentGirisi(
        sened_id=sorgu.sened_id,
        fayl_id=sorgu.fayl_id,
        kontekst=sorgu.kontekst,
    )
    cixis = await AGENTLER["RESEPT_SERFIYYAT"].icra(giris)

    await _jurnal_yaz(cixis, sorgu.sened_id)
    if not cixis.ugurlu:
        METRIKA["xeta"] += 1
        raise HTTPException(status_code=500, detail=cixis.xeta)

    cixaris_id = await _cixaris_yaz(cixis, sorgu.sened_id, sorgu.fayl_id)
    METRIKA["cixaris_yazilan"] += 1

    return {"cixaris_id": cixaris_id, "netice": cixis.netice,
            "token": cixis.giris_token + cixis.cixis_token}
