"""
AI Agent Server — port 8100 (mərkəzdə işləyir).

Endpointlər:
  POST /agent/ocr              — PDF/şəkil qaiməsini işlə
  POST /cixaris/{id}/tesdiq    — Təsdiq + anbar hərəkatı (tranzaksiya)
  POST /agent/anbar            — Qaimə ↔ anbar müqayisəsi (tesdiqdən sonra)
  POST /agent/resept           — Resept ↔ faktiki sərfiyyat
  GET  /health                 — Sağlamlıq
  GET  /metrikalar             — Token xərci statistikası

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
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from minio import Minio
from psycopg.types.json import Jsonb
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

MINIO_MERKEZ_URL = os.getenv("MINIO_MERKEZ_URL", "http://localhost:9010")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY", "zaratuser")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY", "Siyezen2026Minio")
MINIO_BUCKET     = os.getenv("MINIO_BUCKET",     "zarat-sened")

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


def _minio_yukle(acari: str, mime: str) -> tuple[bytes, str]:
    """Sinxron — asyncio.to_thread() içindən çağırılır."""
    endpoint = MINIO_MERKEZ_URL.replace("https://", "").replace("http://", "")
    secure   = MINIO_MERKEZ_URL.startswith("https://")
    mc      = Minio(endpoint, access_key=MINIO_ACCESS_KEY,
                    secret_key=MINIO_SECRET_KEY, secure=secure)
    cavab   = mc.get_object(MINIO_BUCKET, acari)
    melumat = cavab.read()
    cavab.close()
    cavab.release_conn()
    return melumat, mime


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
    sened_id: int


class Anbar_Sorgu(BaseModel):
    sened_id: int


class Tesdiq_Sorgu(BaseModel):
    baxan:   str
    duzelis: dict[str, Any] = {}


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

    # 1. DB-dən fayl meta yüklə
    conn = await _merkez()
    async with conn.cursor() as cur:
        await cur.execute(
            """
            SELECT id, obyekt_acari, mime_tipi
            FROM zavod_sened.fayl
            WHERE sened_id = %s
            ORDER BY id
            LIMIT 1
            """,
            (sorgu.sened_id,),
        )
        fayl_setr = await cur.fetchone()
    if fayl_setr is None:
        raise HTTPException(status_code=404,
                            detail="Bu sənəd üçün fayl tapılmadı.")
    fayl_id, acari, mime_tipi = fayl_setr

    # 2. MinIO-dan endir (sinxron çağırış — to_thread ilə)
    try:
        melumat, mime_tipi = await asyncio.to_thread(
            _minio_yukle, acari, mime_tipi
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"MinIO xətası: {e}")

    giris = AgentGirisi(
        sened_id=sorgu.sened_id,
        fayl_id=fayl_id,
        melumat=melumat,
        mime_tipi=mime_tipi,
    )

    cixis = await AGENTLER["OCR_QAIME"].icra(giris)

    await _jurnal_yaz(cixis, sorgu.sened_id)
    if not cixis.ugurlu:
        METRIKA["xeta"] += 1
        raise HTTPException(status_code=500, detail=cixis.xeta)

    cixaris_id = await _cixaris_yaz(cixis, sorgu.sened_id, fayl_id)
    METRIKA["cixaris_yazilan"] += 1

    return {
        "cixaris_id": cixaris_id,
        "netice":     cixis.netice,
        "eminlik":    cixis.eminlik,
        "token":      cixis.giris_token + cixis.cixis_token,
    }


@app.post("/cixaris/{cixaris_id}/tesdiq")
async def cixaris_tesdiq(cixaris_id: int, sorgu: Tesdiq_Sorgu):
    """
    Bir tranzaksiyada:
      a) zavod_ai.cixaris — status, insan_duzelisi, baxan
      b) zavod_sened.sened — status='tesdiqlendi', metadata=final netice
      c) zavod_anbar.herekat — hər setir üçün (pg_trgm uzlaşması)
    Oxşarlıq < 0.4 olan material varsa → 409, heç nə yazılmır.
    """
    async with await psycopg.AsyncConnection.connect(MERKEZ_DSN) as tx:
        async with tx.cursor() as cur:

            # ── Cixarış + kilidlə ─────────────────────────────────────────
            await cur.execute(
                "SELECT sened_id, netice FROM zavod_ai.cixaris WHERE id = %s",
                (cixaris_id,),
            )
            row = await cur.fetchone()
            if row is None:
                raise HTTPException(status_code=404, detail="Cixariş tapılmadı.")
            sened_id, netice = row

            await cur.execute(
                "SELECT novu FROM zavod_sened.sened WHERE id = %s",
                (sened_id,),
            )
            sened_novu = (await cur.fetchone())[0]

            # ── Final nəticə (düzəlişlər üzərindən) ─────────────────────
            final_netice  = {**netice, **sorgu.duzelis}
            cixaris_status = "duzelis_edildi" if sorgu.duzelis else "tesdiqlendi"

            # ── Material uzlaşması — YAZMAdan əvvəl yoxla ────────────────
            herekat_novu = {"QAIME_MEDAXIL": "MEDAXIL",
                            "QAIME_MEXARIC": "MEXARIC"}.get(sened_novu)

            tapilmayan: list[str] = []
            eslesenler: list[tuple] = []   # (kod, miqdar, vahid_qiymet)

            if herekat_novu:
                for setir in final_netice.get("setirler", []):
                    mat_ad = setir.get("material", "")
                    await cur.execute(
                        """
                        SELECT kod,
                               greatest(
                                   similarity(lower(ad),  lower(%s)),
                                   similarity(lower(kod), lower(%s))
                               ) AS oxsarliq
                        FROM zavod_anbar.material
                        WHERE aktiv
                        ORDER BY oxsarliq DESC
                        LIMIT 1
                        """,
                        (mat_ad, mat_ad),
                    )
                    m = await cur.fetchone()
                    if m is None or m[1] < 0.4:
                        tapilmayan.append(mat_ad)
                    else:
                        eslesenler.append(
                            (m[0], setir.get("miqdar"), setir.get("vahid_qiymet"))
                        )

                if tapilmayan:
                    raise HTTPException(
                        status_code=409,
                        detail=f"Material tapılmadı (bazaya əlavə edin): "
                               f"{', '.join(tapilmayan)}",
                    )

            # ── Hamısı OK — indi yaz ──────────────────────────────────────
            await cur.execute(
                """
                UPDATE zavod_ai.cixaris
                SET status         = %s,
                    insan_duzelisi = %s,
                    baxan          = %s,
                    baxis_vaxti    = now()
                WHERE id = %s
                """,
                (cixaris_status,
                 Jsonb(sorgu.duzelis) if sorgu.duzelis else None,
                 sorgu.baxan,
                 cixaris_id),
            )

            await cur.execute(
                """
                UPDATE zavod_sened.sened
                SET status   = 'tesdiqlendi',
                    metadata = %s
                WHERE id = %s
                """,
                (Jsonb(final_netice), sened_id),
            )

            for material_kod, miqdar, vahid_qiymet in eslesenler:
                await cur.execute(
                    """
                    INSERT INTO zavod_anbar.herekat
                        (material_kod, novu, miqdar, vahid_qiymet, sened_id, menbe)
                    VALUES (%s, %s, %s, %s, %s, 'AI_TESDIQ')
                    """,
                    (material_kod, herekat_novu, miqdar, vahid_qiymet, sened_id),
                )

    log.info("Təsdiq: cixaris_id=%d sened_id=%d status=%s herekat=%d",
             cixaris_id, sened_id, cixaris_status, len(eslesenler))
    return {
        "ok":        True,
        "cixaris_id": cixaris_id,
        "sened_id":   sened_id,
        "herekat_say": len(eslesenler),
    }


@app.post("/agent/anbar", status_code=201)
async def anbar_icra(sorgu: Anbar_Sorgu):
    """
    Təsdiqlənmiş qaiməni anbar qalığı ilə müqayisə edir.
    Bütün rəqəmlər SQL-dən; LLM yalnız izah yazır.
    """
    if not await _gunluk_token_yoxla():
        raise HTTPException(status_code=429, detail="Günlük token limiti aşıldı.")

    conn = await _merkez()

    # 1. Sənəd yoxla — tesdiqlendi olmalı
    async with conn.cursor() as cur:
        await cur.execute(
            """
            SELECT novu, nomre, sened_tarixi, metadata
            FROM zavod_sened.sened
            WHERE id = %s AND status = 'tesdiqlendi'
            """,
            (sorgu.sened_id,),
        )
        sened_row = await cur.fetchone()
    if sened_row is None:
        raise HTTPException(status_code=404,
                            detail="Sənəd tapılmadı və ya hələ təsdiqlənməmişdir.")

    sened_novu, nomre, sened_tarixi, metadata = sened_row
    setirler = metadata.get("setirler", [])

    # 2. Hər setir üçün: material uzlaşması + anomaliya
    uygunlasma   = []
    qaliq_cache: dict = {}   # kod → dict (LLM-ə ötürmək üçün)

    for setir in setirler:
        mat_ad  = setir.get("material", "")
        vahid_q = setir.get("vahid_qiymet")

        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT m.kod, m.ad,
                       greatest(
                           similarity(lower(m.ad),  lower(%s)),
                           similarity(lower(m.kod), lower(%s))
                       ) AS oxsarliq,
                       q.qaliq, q.min_qaliq, q.vahid, q.orta_qiymet_30g
                FROM zavod_anbar.material m
                LEFT JOIN zavod_anbar.qaliq q ON q.kod = m.kod
                WHERE m.aktiv
                ORDER BY oxsarliq DESC
                LIMIT 1
                """,
                (mat_ad, mat_ad),
            )
            m = await cur.fetchone()

        problemler: list[str] = []
        if m is None or m[2] < 0.4:
            problemler.append("material_tapilmadi")
            uygunlasma.append({"material_ad": mat_ad, "tapildi": False,
                               "material_kod": None, "problemler": problemler})
            continue

        kod, ad_db, oxs, qaliq_val, min_q, vahid, orta_q = m
        qaliq_cache[kod] = {
            "kod": kod, "ad": ad_db, "vahid": vahid,
            "qaliq":     float(qaliq_val or 0),
            "min_qaliq": float(min_q) if min_q else None,
        }

        # Qalıq xəbərdarlığı
        if min_q is not None and float(qaliq_val or 0) < float(min_q):
            problemler.append("min_qaliq_asagi")

        # Qiymət anomaliyası (>25%)
        if vahid_q and orta_q and float(orta_q) > 0:
            if abs(float(vahid_q) - float(orta_q)) / float(orta_q) > 0.25:
                problemler.append("qiymet_anomaliya")

        uygunlasma.append({
            "material_ad":  mat_ad,
            "tapildi":      True,
            "material_kod": kod,
            "oxsarliq":     round(float(oxs), 2),
            "miqdar":       setir.get("miqdar"),
            "qaliq":        float(qaliq_val or 0),
            "problemler":   problemler,
        })

    # 3. Təkrar qaimə yoxlaması (eyni nomre + tarix + cemi_mebleg)
    cemi = metadata.get("cemi_mebleg")
    async with conn.cursor() as cur:
        await cur.execute(
            """
            SELECT count(*) FROM zavod_sened.sened
            WHERE nomre = %s
              AND sened_tarixi = %s
              AND (metadata->>'cemi_mebleg')::numeric
                    IS NOT DISTINCT FROM %s::numeric
              AND id != %s
              AND status = 'tesdiqlendi'
            """,
            (nomre, sened_tarixi, cemi, sorgu.sened_id),
        )
        tekrar = (await cur.fetchone())[0]

    if tekrar > 0:
        for u in uygunlasma:
            u["problemler"].append("tekrar_qaime")

    kontekst = {
        "sened_netice": metadata,
        "anbar_qaliq":  list(qaliq_cache.values()),
        "uygunlasma":   uygunlasma,
    }

    giris = AgentGirisi(sened_id=sorgu.sened_id, fayl_id=None, kontekst=kontekst)
    cixis = await AGENTLER["ANBAR_MUQAYISE"].icra(giris)

    await _jurnal_yaz(cixis, sorgu.sened_id)
    if not cixis.ugurlu:
        METRIKA["xeta"] += 1
        raise HTTPException(status_code=500, detail=cixis.xeta)

    cixaris_id = await _cixaris_yaz(cixis, sorgu.sened_id, None)
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
