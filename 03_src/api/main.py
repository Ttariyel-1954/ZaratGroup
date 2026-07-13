"""Zarat Faza 2 - Zavod telemetriya API-si (MQTT + HTTP + Alert)."""
from .loglama import qur as loglama_qur
loglama_qur()

import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Query
import psycopg

from .konfiq import VERSIYA
from .baza import (hovuz, HEDLER, hedleri_yukle,
                   olcme_yaz, son_olcmeler, cihazlar)
from .modeller import (OlcmeIn, OlcmeOut, CihazOut,
                       QebulCavabi, SaglamliqCavabi)
from . import mqtt as mqtt_modul
from . import alert as alert_modul
from . import nezaretci as nezaret_modul
from .yazici import yazici_dovru, YAZICI_METRIKA
from .bildiris import BILDIRIS_METRIKA
from .senedler import router as sened_router

log = logging.getLogger("zarat.api")

METRIKA = {"qebul": 0, "anomal": 0, "xeta": 0,
           "basladi": datetime.now(timezone.utc)}


@asynccontextmanager
async def lifespan(app: FastAPI):
    await hovuz.open()
    await hovuz.wait()
    say = await hedleri_yukle()
    log.info("Baza hazir - %d cihaz", say)

    loop = asyncio.get_running_loop()
    novbe = mqtt_modul.basla(loop)

    yazici_task = asyncio.create_task(yazici_dovru(novbe))
    nezaret_task = asyncio.create_task(nezaret_modul.nezaretci_dovru())

    log.info("Servis hazir - versiya %s", VERSIYA)
    yield

    # ---- SONME (sira vacibdir) ----
    log.info("Sonme basladi...")
    mqtt_modul.dayandir()
    try:
        await asyncio.wait_for(novbe.join(), timeout=5.0)
    except asyncio.TimeoutError:
        log.warning("Novbede %d mesaj qaldi", novbe.qsize())

    for task in (yazici_task, nezaret_task):
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass

    await hovuz.close()
    log.info("Servis sondu.")


app = FastAPI(
    title="Zarat Zavod Telemetriya API",
    description="Siyezen yem zavodu - MQTT + HTTP + Alert muherriki",
    version=VERSIYA,
    lifespan=lifespan,
)

# Faza 3 — Sənəd endpointləri
app.include_router(sened_router)


@app.get("/health", response_model=SaglamliqCavabi, tags=["Sistem"])
async def saglamliq():
    try:
        async with hovuz.connection() as conn:
            async with conn.cursor() as cur:
                await cur.execute("SELECT 1")
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Baza elcatmazdir: {e}")
    return SaglamliqCavabi(status="ok", baza="ok",
                           cihaz_sayi=len(HEDLER), versiya=VERSIYA)


@app.get("/metrikalar", tags=["Sistem"])
async def metrikalar():
    novbe = mqtt_modul.novbe
    muddet = datetime.now(timezone.utc) - METRIKA["basladi"]
    return {
        "mqtt": {**mqtt_modul.MQTT_METRIKA,
                 "novbe_uzunlugu": novbe.qsize() if novbe else 0},
        "yazici": YAZICI_METRIKA,
        "alert": alert_modul.ALERT_METRIKA,
        "nezaretci": nezaret_modul.NEZARET_METRIKA,
        "bildiris": BILDIRIS_METRIKA,
        "http": {"qebul": METRIKA["qebul"], "anomal": METRIKA["anomal"],
                 "xeta": METRIKA["xeta"]},
        "isleme_saniye": int(muddet.total_seconds()),
        "cihaz_sayi": len(HEDLER),
        "versiya": VERSIYA,
    }


@app.post("/olcme", response_model=QebulCavabi, status_code=201, tags=["Olcme"])
async def olcme_qebul(olcme: OlcmeIn):
    if olcme.cihaz_kod not in HEDLER:
        METRIKA["xeta"] += 1
        raise HTTPException(
            status_code=404,
            detail=f"Namelum cihaz: {olcme.cihaz_kod}. "
                   f"Taninanlar: {sorted(HEDLER.keys())}")

    try:
        netice = await olcme_yaz(olcme.cihaz_kod, olcme.olcme_vaxti, olcme.qiymet)
    except psycopg.Error as e:
        METRIKA["xeta"] += 1
        raise HTTPException(status_code=503, detail=f"Baza xetasi: {e}")

    METRIKA["qebul"] += 1
    if netice["keyfiyyet"] == 0:
        METRIKA["anomal"] += 1

    return QebulCavabi(
        status="anomal" if netice["keyfiyyet"] == 0 else "qebul",
        cihaz_kod=olcme.cihaz_kod, qiymet=olcme.qiymet,
        keyfiyyet=netice["keyfiyyet"], xeberdarliq=netice["xeberdarliq"])


@app.get("/olcme/son", response_model=list[OlcmeOut], tags=["Olcme"])
async def olcme_son(limit: int = Query(20, ge=1, le=500),
                    cihaz: str | None = Query(None)):
    return await son_olcmeler(limit=limit, cihaz=cihaz)


@app.get("/cihazlar", response_model=list[CihazOut], tags=["Cihaz"])
async def cihaz_siyahisi():
    return await cihazlar()


@app.post("/cihazlar/yenile", tags=["Cihaz"])
async def hedleri_yenile():
    say = await hedleri_yukle()
    return {"status": "yenilendi", "cihaz_sayi": say,
            "cihazlar": sorted(HEDLER.keys())}


# ============ YENI: Xeberdarliq endpoint-leri ============

@app.get("/xeberdarliq/aktiv", tags=["Xeberdarliq"])
async def aktiv_alertler():
    """Hell olunmamis alertler - kritikler onde."""
    sql = """
        SELECT id, cihaz_kod, novu, seviyye, mesaj,
               acilma_vaxti, tetik_sayi,
               ilk_qiymet, son_qiymet, pik_qiymet,
               now() - acilma_vaxti AS muddet
        FROM xeberdarliq
        WHERE hell_olundu = FALSE
        ORDER BY (seviyye = 'kritik') DESC, acilma_vaxti ASC
    """
    async with hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(sql)
            setirler = await cur.fetchall()

    return [
        {"id": r[0], "cihaz_kod": r[1], "novu": r[2],
         "seviyye": r[3], "mesaj": r[4],
         "acilma_vaxti": r[5], "tetik_sayi": r[6],
         "ilk_qiymet": float(r[7]) if r[7] is not None else None,
         "son_qiymet": float(r[8]) if r[8] is not None else None,
         "pik_qiymet": float(r[9]) if r[9] is not None else None,
         "muddet": str(r[10]) if r[10] else None}
        for r in setirler
    ]


@app.post("/xeberdarliq/{alert_id}/hell-et", tags=["Xeberdarliq"])
async def alerti_hell_et(alert_id: int, qeyd: str | None = None):
    """Operator alerti el ile baglayir."""
    sql = """
        UPDATE xeberdarliq
        SET hell_olundu = TRUE, baglanma_vaxti = now()
        WHERE id = %s AND hell_olundu = FALSE
        RETURNING id, cihaz_kod, novu,
                  (baglanma_vaxti - acilma_vaxti) AS muddet
    """
    async with hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(sql, (alert_id,))
            setir = await cur.fetchone()

    if setir is None:
        raise HTTPException(
            status_code=404,
            detail=f"Alert {alert_id} tapilmadi ve ya artiq baglanib")

    log.info("Operator alerti bagladi: id=%s, qeyd=%s", alert_id, qeyd)
    return {"status": "hell olundu", "id": setir[0],
            "cihaz_kod": setir[1], "muddet": str(setir[3])}


@app.get("/xeberdarliq/tarixce", tags=["Xeberdarliq"])
async def alert_tarixcesi(limit: int = Query(50, ge=1, le=500),
                          cihaz: str | None = Query(None)):
    sql = """
        SELECT id, cihaz_kod, novu, seviyye, tetik_sayi,
               acilma_vaxti, baglanma_vaxti, pik_qiymet, hell_olundu
        FROM xeberdarliq
        WHERE (%s::text IS NULL OR cihaz_kod = %s)
        ORDER BY acilma_vaxti DESC NULLS LAST
        LIMIT %s
    """
    async with hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(sql, (cihaz, cihaz, limit))
            setirler = await cur.fetchall()

    return [
        {"id": r[0], "cihaz_kod": r[1], "novu": r[2],
         "seviyye": r[3], "tetik_sayi": r[4],
         "acilma_vaxti": r[5], "baglanma_vaxti": r[6],
         "pik_qiymet": float(r[7]) if r[7] is not None else None,
         "hell_olundu": r[8]}
        for r in setirler
    ]
