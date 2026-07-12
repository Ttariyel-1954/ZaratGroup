"""Zarat Faza 2 - Zavod telemetriya API-si (MQTT + HTTP)."""
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
from .yazici import yazici_dovru, YAZICI_METRIKA

log = logging.getLogger("zarat.api")

METRIKA = {"qebul": 0, "anomal": 0, "xeta": 0,
           "basladi": datetime.now(timezone.utc)}


@asynccontextmanager
async def lifespan(app: FastAPI):
    # ---------- BASLANGIC ----------
    await hovuz.open()
    await hovuz.wait()
    say = await hedleri_yukle()
    log.info("Baza hazir - %d cihaz", say)

    loop = asyncio.get_running_loop()
    novbe = mqtt_modul.basla(loop)
    yazici_task = asyncio.create_task(yazici_dovru(novbe))
    log.info("Servis hazir - versiya %s", VERSIYA)

    yield

    # ---------- SONME (sira vacibdir!) ----------
    log.info("Sonme basladi...")
    mqtt_modul.dayandir()                       # 1) yeni mesaj gelmesin

    try:                                        # 2) novbedeki qaliq yazilsin
        await asyncio.wait_for(novbe.join(), timeout=5.0)
    except asyncio.TimeoutError:
        log.warning("Novbede %d mesaj qaldi", novbe.qsize())

    yazici_task.cancel()                        # 3) yazici dayansin
    try:
        await yazici_task
    except asyncio.CancelledError:
        pass

    await hovuz.close()                         # 4) hovuz baglansin
    log.info("Servis sondu.")


app = FastAPI(
    title="Zarat Zavod Telemetriya API",
    description="Siyezen yem zavodu - MQTT + HTTP telemetriya",
    version=VERSIYA,
    lifespan=lifespan,
)


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
        "mqtt": {
            **mqtt_modul.MQTT_METRIKA,
            "novbe_uzunlugu": novbe.qsize() if novbe else 0,
        },
        "yazici": YAZICI_METRIKA,
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
                   f"Taninanlar: {sorted(HEDLER.keys())}",
        )

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
        cihaz_kod=olcme.cihaz_kod,
        qiymet=olcme.qiymet,
        keyfiyyet=netice["keyfiyyet"],
        xeberdarliq=netice["xeberdarliq"],
    )


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
