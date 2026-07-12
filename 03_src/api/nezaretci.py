"""
Nezaretci - susan cihazlari tutur.
Fon tapsirigi: her 60 saniyede butun cihazlari yoxlayir.
"""
import asyncio
import logging

from .baza import hovuz
from .bildiris import bildiris_gonder

log = logging.getLogger("zarat.nezaretci")

YOXLAMA_INTERVAL = 60     # saniye
SUSMA_HEDD_DEQ = 5        # 5 deqiqedir mesaj yoxdursa -> susub

NEZARET_METRIKA = {"susan": 0, "berpa": 0, "yoxlama": 0}

SQL_SUSANLAR = """
WITH son_olcme AS (
    SELECT c.kod, max(o.olcme_vaxti) AS son_vaxt
    FROM cihaz c
    LEFT JOIN olcme o ON o.cihaz_kod = c.kod
    WHERE c.status = 'aktiv'
    GROUP BY c.kod
)
SELECT kod, son_vaxt
FROM son_olcme
WHERE son_vaxt IS NULL
   OR son_vaxt < now() - (%(hedd)s || ' minutes')::interval
"""

SQL_SUSMA_ALERT = """
INSERT INTO xeberdarliq (
    cihaz_kod, olcme_vaxti, qiymet, novu, mesaj,
    seviyye, acilma_vaxti, tetik_sayi,
    ilk_qiymet, son_qiymet, pik_qiymet, hell_olundu
)
VALUES (%(kod)s, now(), 0, 'cihaz_susur', %(mesaj)s,
        'kritik', now(), 1, 0, 0, 0, FALSE)
ON CONFLICT (cihaz_kod, novu) WHERE hell_olundu = FALSE
DO UPDATE SET
    tetik_sayi = xeberdarliq.tetik_sayi + 1,
    mesaj      = EXCLUDED.mesaj
RETURNING id, (xmax = 0) AS yeni
"""

SQL_SUSMA_BAGLA = """
UPDATE xeberdarliq
SET hell_olundu    = TRUE,
    baglanma_vaxti = now()
WHERE novu = 'cihaz_susur'
  AND hell_olundu = FALSE
  AND cihaz_kod IN (
      SELECT DISTINCT cihaz_kod FROM olcme
      WHERE olcme_vaxti > now() - (%(hedd)s || ' minutes')::interval
  )
RETURNING cihaz_kod, (baglanma_vaxti - acilma_vaxti) AS muddet
"""


async def bir_yoxlama():
    """Bir dovr: EVVELCE berpa olunanlari bagla, SONRA susanlari tap."""
    NEZARET_METRIKA["yoxlama"] += 1
    yeni_susanlar = []

    async with hovuz.connection() as conn:
        # 1) Berpa olunanlari bagla (EVVELCE bu!)
        async with conn.cursor() as cur:
            await cur.execute(SQL_SUSMA_BAGLA, {"hedd": SUSMA_HEDD_DEQ})
            for kod, muddet in await cur.fetchall():
                NEZARET_METRIKA["berpa"] += 1
                log.info("CIHAZ BERPA OLUNDU: %s (%s susmusdu)", kod, muddet)

        # 2) Susanlari tap
        async with conn.cursor() as cur:
            await cur.execute(SQL_SUSANLAR, {"hedd": SUSMA_HEDD_DEQ})
            susanlar = await cur.fetchall()

        # 3) Her susan ucun alert
        for kod, son_vaxt in susanlar:
            mesaj = (f"{kod}: {SUSMA_HEDD_DEQ} deqiqedir mesaj yoxdur "
                     f"(son: {son_vaxt or 'hec vaxt'})")
            async with conn.cursor() as cur:
                await cur.execute(SQL_SUSMA_ALERT, {"kod": kod, "mesaj": mesaj})
                alert_id, yeni = await cur.fetchone()

            if yeni:
                NEZARET_METRIKA["susan"] += 1
                log.error("CIHAZ SUSDU: %s", mesaj)
                yeni_susanlar.append((kod, mesaj))

    # 4) Bildiris - TRANZAKSIYADAN SONRA
    for kod, mesaj in yeni_susanlar:
        await bildiris_gonder(baslik=f"CIHAZ SUSDU: {kod}", metn=mesaj)


async def nezaretci_dovru():
    """Fon tapsirigi - olmemelidir."""
    log.info("Nezaretci basladi (interval=%ds, hedd=%d deq.)",
             YOXLAMA_INTERVAL, SUSMA_HEDD_DEQ)
    while True:
        try:
            await asyncio.sleep(YOXLAMA_INTERVAL)   # SLEEP EVVELDE!
            await bir_yoxlama()
        except asyncio.CancelledError:
            log.info("Nezaretci dayandirilir...")
            raise
        except Exception as e:
            log.exception("Nezaretcide xeta: %s", e)
