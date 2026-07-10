"""
Sinxronizasiya servisi - zavod_edge_db -> zarat_erp_2 (outbox modeli).
Fayl: 03_src/sync/sync_servis.py
Ishe salmaq:  python sync_servis.py
Dayandirmaq:  CTRL+C
"""
import os
import time
import logging
import psycopg
from dotenv import load_dotenv

_KONF = os.path.join(os.path.dirname(__file__), "..", "..", "01_config", ".env")
load_dotenv(_KONF)

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s  %(levelname)s  %(message)s")
log = logging.getLogger("sync")

# ayarlar
BATCH = 200          # her tsikilde en cox nece setir
INTERVAL = 10        # tsikllerarasi saniye
ZAVOD = "siyezen"


def edge_dsn():
    return (f"host={os.getenv('EDGE_DB_HOST','localhost')} "
            f"port={os.getenv('EDGE_DB_PORT','5434')} "
            f"dbname={os.getenv('EDGE_DB_NAME','zavod_edge_db')} "
            f"user={os.getenv('EDGE_DB_USER','royatalibova')}")


def merkez_dsn():
    return (f"host={os.getenv('MERKEZ_DB_HOST','localhost')} "
            f"port={os.getenv('MERKEZ_DB_PORT','5432')} "
            f"dbname={os.getenv('MERKEZ_DB_NAME','zarat_erp_2')} "
            f"user={os.getenv('MERKEZ_DB_USER','royatalibova')}")


def bir_tsikl(edge, merkez):
    """Bir sinxronizasiya tsikli. Gonderilen setir sayini qaytarir."""
    # 1) gonderilmemis setirleri oxu
    with edge.cursor() as cur:
        cur.execute("""
            SELECT id, cihaz_kod, olcme_vaxti, qiymet
            FROM olcme
            WHERE sync_status = 0
            ORDER BY olcme_vaxti
            LIMIT %s
        """, (BATCH,))
        setirler = cur.fetchall()

    if not setirler:
        return 0

    # 2) merkeze yaz (idempotent: eyni edge_id tekrar dusmesin)
    with merkez.cursor() as mcur:
        for (edge_id, cihaz_kod, vaxt, qiymet) in setirler:
            mcur.execute("""
                INSERT INTO zavod_telemetriya.olcme
                    (zavod, edge_id, cihaz_kod, olcme_vaxti, qiymet)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (zavod, edge_id) DO NOTHING
            """, (ZAVOD, edge_id, cihaz_kod, vaxt, qiymet))
    merkez.commit()

    # 3) menbede sync_status = 1 isarele
    ids = [r[0] for r in setirler]
    with edge.cursor() as cur:
        cur.execute("""
            UPDATE olcme SET sync_status = 1
            WHERE id = ANY(%s)
        """, (ids,))
    edge.commit()

    return len(setirler)


def main():
    log.info("Sync servis basladi. CTRL+C ile dayandirin.")
    log.info(f"Edge: {os.getenv('EDGE_DB_NAME')}  ->  "
             f"Merkez: {os.getenv('MERKEZ_DB_NAME')}")

    edge = psycopg.connect(edge_dsn())
    merkez = psycopg.connect(merkez_dsn())

    try:
        while True:
            try:
                say = bir_tsikl(edge, merkez)
                if say > 0:
                    log.info(f"Sinxronlasdirildi: {say} olcme")
                else:
                    log.info("Yeni olcme yoxdur")
            except Exception as e:
                # xeta olsa - bagli qalma, novbeti tsikilde tekrar cehd
                log.error(f"Tsikl xetasi: {e}")
                edge.rollback()
                merkez.rollback()
            time.sleep(INTERVAL)
    except KeyboardInterrupt:
        log.info("Dayandirilir...")
    finally:
        edge.close()
        merkez.close()
        log.info("Baglantilar baglandi.")


if __name__ == "__main__":
    main()
