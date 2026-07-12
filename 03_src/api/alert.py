"""
Alert muherriki - Ders 06.
Veziyyet masini: NORMAL -> GOZLEME -> AKTIV -> BAGLANMIS
Dord mexanizm: ardicilliq, debouncing, hysteresis, seviyyeler.
"""
import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from .baza import HEDLER

log = logging.getLogger("zarat.alert")

# Ardicilliq sayqaclari - YADDASDA
SAYGAC: dict = {}

ALERT_METRIKA = {"acilan": 0, "yenilenen": 0,
                 "baglanan": 0, "kritik": 0, "udulan": 0}


@dataclass
class AlertEmri:
    """Alert muherrikinin qerari - yazici bunu icra edecek."""
    emr: str                          # "ac_ve_ya_yenile" | "bagla" | "hec_ne"
    cihaz_kod: str
    novu: Optional[str] = None        # "yuxari_hedd" | "asagi_hedd"
    seviyye: str = "xeberdarliq"
    qiymet: float = 0.0
    olcme_vaxti: Optional[datetime] = None
    mesaj: str = ""


def sayqac_artir(kod, novu):
    d = SAYGAC.setdefault(kod, {})
    d[novu] = d.get(novu, 0) + 1
    return d[novu]


def sayqac_sifirla(kod, novu):
    SAYGAC.setdefault(kod, {})[novu] = 0


def qiymetlendir(kod, qiymet, vaxt):
    """
    Bir olcmeni qiymetlendirir ve NE EDILMELI oldugunu qaytarir.
    Bazaya YAZMIR - yalniz QERAR verir. Test etmek asandir.
    """
    h = HEDLER.get(kod)
    if h is None:
        return AlertEmri("hec_ne", kod)

    vahid = h["vahid"]

    # ---- 1. YUXARI HEDD ----
    if qiymet > h["max"]:
        say = sayqac_artir(kod, "yuxari_hedd")
        if say < h["ardicil_hedd"]:
            ALERT_METRIKA["udulan"] += 1
            return AlertEmri("hec_ne", kod, "yuxari_hedd")

        seviyye = "kritik" if qiymet >= h["kritik_yuxari"] else "xeberdarliq"
        return AlertEmri(
            emr="ac_ve_ya_yenile", cihaz_kod=kod, novu="yuxari_hedd",
            seviyye=seviyye, qiymet=qiymet, olcme_vaxti=vaxt,
            mesaj=f"{kod}: {qiymet} {vahid} > maks {h['max']} {vahid}",
        )

    # ---- 2. ASAGI HEDD ----
    if qiymet < h["min"]:
        say = sayqac_artir(kod, "asagi_hedd")
        if say < h["ardicil_hedd"]:
            ALERT_METRIKA["udulan"] += 1
            return AlertEmri("hec_ne", kod, "asagi_hedd")

        seviyye = "kritik" if qiymet <= h["kritik_asagi"] else "xeberdarliq"
        return AlertEmri(
            emr="ac_ve_ya_yenile", cihaz_kod=kod, novu="asagi_hedd",
            seviyye=seviyye, qiymet=qiymet, olcme_vaxti=vaxt,
            mesaj=f"{kod}: {qiymet} {vahid} < min {h['min']} {vahid}",
        )

    # ---- 3. HYSTERESIS ZOLAGI ----
    # Hedler arasindadir, AMMA berpa heddine catmayib -> alert ACIQ qalir.
    # Sayqaci da SIFIRLAMIRIQ - problem hele bitmeyib.
    if qiymet > h["berpa_yuxari"] or qiymet < h["berpa_asagi"]:
        return AlertEmri("hec_ne", kod)

    # ---- 4. TAM NORMAL -> ALERTLERI BAGLA ----
    sayqac_sifirla(kod, "yuxari_hedd")
    sayqac_sifirla(kod, "asagi_hedd")

    return AlertEmri(emr="bagla", cihaz_kod=kod,
                     qiymet=qiymet, olcme_vaxti=vaxt)


SQL_UPSERT = """
INSERT INTO xeberdarliq (
    cihaz_kod, olcme_vaxti, qiymet, novu, mesaj,
    seviyye, acilma_vaxti, tetik_sayi,
    ilk_qiymet, son_qiymet, pik_qiymet, hell_olundu
)
VALUES (%(kod)s, %(vaxt)s, %(qiymet)s, %(novu)s, %(mesaj)s,
        %(seviyye)s, %(vaxt)s, 1,
        %(qiymet)s, %(qiymet)s, %(qiymet)s, FALSE)
ON CONFLICT (cihaz_kod, novu) WHERE hell_olundu = FALSE
DO UPDATE SET
    tetik_sayi = xeberdarliq.tetik_sayi + 1,
    son_qiymet = EXCLUDED.son_qiymet,
    qiymet     = EXCLUDED.qiymet,
    mesaj      = EXCLUDED.mesaj,
    pik_qiymet = CASE
        WHEN xeberdarliq.novu = 'yuxari_hedd'
            THEN GREATEST(xeberdarliq.pik_qiymet, EXCLUDED.pik_qiymet)
        ELSE LEAST(xeberdarliq.pik_qiymet, EXCLUDED.pik_qiymet)
    END,
    seviyye = CASE
        WHEN EXCLUDED.seviyye = 'kritik' THEN 'kritik'
        ELSE xeberdarliq.seviyye
    END
RETURNING id, (xmax = 0) AS yeni_yaradildi, seviyye, tetik_sayi
"""


async def alerti_yaz(conn, emr):
    """Upsert: yoxdursa YARAT, varsa YENILE. Atomikdir."""
    async with conn.cursor() as cur:
        await cur.execute(SQL_UPSERT, {
            "kod": emr.cihaz_kod,
            "vaxt": emr.olcme_vaxti,
            "qiymet": emr.qiymet,
            "novu": emr.novu,
            "mesaj": emr.mesaj,
            "seviyye": emr.seviyye,
        })
        setir = await cur.fetchone()

    if setir is None:
        return None

    alert_id, yeni, seviyye, tetik = setir

    if yeni:
        ALERT_METRIKA["acilan"] += 1
        log.warning("ALERT ACILDI [%s] %s - %s",
                    seviyye.upper(), emr.cihaz_kod, emr.mesaj)
    else:
        ALERT_METRIKA["yenilenen"] += 1

    if seviyye == "kritik":
        ALERT_METRIKA["kritik"] += 1

    return {"id": alert_id, "yeni": yeni,
            "seviyye": seviyye, "tetik_sayi": tetik}


SQL_BAGLA = """
UPDATE xeberdarliq
SET hell_olundu    = TRUE,
    baglanma_vaxti = %(vaxt)s,
    son_qiymet     = %(qiymet)s
WHERE cihaz_kod = %(kod)s
  AND hell_olundu = FALSE
  AND novu IN ('yuxari_hedd', 'asagi_hedd')
RETURNING id, novu, seviyye, tetik_sayi,
          (baglanma_vaxti - acilma_vaxti) AS muddet
"""


async def alertleri_bagla(conn, emr):
    """
    Hedd alertlerini baglayir (deyer normala qayidib).
    cihaz_susur alertine TOXUNMUR - onu nezaretci idare edir.
    """
    async with conn.cursor() as cur:
        await cur.execute(SQL_BAGLA, {
            "kod": emr.cihaz_kod,
            "vaxt": emr.olcme_vaxti,
            "qiymet": emr.qiymet,
        })
        baglananlar = await cur.fetchall()

    for alert_id, novu, seviyye, tetik, muddet in baglananlar:
        ALERT_METRIKA["baglanan"] += 1
        log.info("ALERT BAGLANDI %s [%s] - %s erzinde, %d tetik",
                 emr.cihaz_kod, novu, muddet, tetik)

    return baglananlar
