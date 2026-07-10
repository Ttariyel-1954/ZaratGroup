"""
Anomaliya askarlama - olcmeni heddlerle muqayise edir.
Fayl: 03_src/alert/anomaliya.py
"""
import logging

log = logging.getLogger("anomaliya")

# cihaz_kod -> (min_hedd, max_hedd, vahid, ad)
_heddler = {}


def heddleri_yukle(conn):
    """sensor_tipi ve cihaz cedvellerinden heddleri yaddasa yuklyeyir."""
    global _heddler
    _heddler = {}
    with conn.cursor() as cur:
        cur.execute("""
            SELECT c.kod, t.min_hedd, t.max_hedd, t.vahid, t.ad
            FROM cihaz c
            JOIN sensor_tipi t ON c.sensor_tipi_kod = t.kod
        """)
        for kod, minh, maxh, vahid, ad in cur.fetchall():
            _heddler[kod] = {
                "min": float(minh) if minh is not None else None,
                "max": float(maxh) if maxh is not None else None,
                "vahid": vahid,
                "ad": ad,
            }
    log.info(f"Heddler yuklendi: {len(_heddler)} cihaz")
    return _heddler


def yoxla(cihaz_kod, qiymet):
    """
    Bir olcmeni yoxlayir.
    Qaytarir: None (normal) ve ya (novu, mesaj) (anomaliya).
    """
    h = _heddler.get(cihaz_kod)
    if h is None:
        return None  # namelum cihaz - yoxlanmir

    if h["max"] is not None and qiymet > h["max"]:
        mesaj = (f"{h['ad']}: {qiymet} {h['vahid']} "
                 f"(max hedd {h['max']} {h['vahid']} asildi)")
        return ("yuxari_hedd", mesaj)

    if h["min"] is not None and qiymet < h["min"]:
        mesaj = (f"{h['ad']}: {qiymet} {h['vahid']} "
                 f"(min hedd {h['min']} {h['vahid']} altinda)")
        return ("asagi_hedd", mesaj)

    return None


def xeberdarliq_yaz(conn, cihaz_kod, olcme_vaxti, qiymet, novu, mesaj):
    """xeberdarliq cedveline qeyd yazir."""
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO xeberdarliq
                (cihaz_kod, olcme_vaxti, qiymet, novu, mesaj)
            VALUES (%s, %s, %s, %s, %s)
        """, (cihaz_kod, olcme_vaxti, qiymet, novu, mesaj))
