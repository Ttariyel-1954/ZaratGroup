"""
Simulyator -> zavod_edge_db birbaa yazma testi.
Fayl: 03_src/sensorlar/baza_yaz_test.py
Ishe salmaq:  python baza_yaz_test.py
"""
import os
import time
import psycopg
from dotenv import load_dotenv
from sensorlar import butun_sensorlar

# .env faylini oxu (layihe koku)
load_dotenv(os.path.join(os.path.dirname(__file__), "..", "..", "01_config", ".env"))

DSN = (
    f"host={os.getenv('EDGE_DB_HOST')} "
    f"port={os.getenv('EDGE_DB_PORT')} "
    f"dbname={os.getenv('EDGE_DB_NAME')} "
    f"user={os.getenv('EDGE_DB_USER')}"
)


def main():
    sensorlar = butun_sensorlar()
    print("Baza yazma  5 dovr, her dovrde 5 sensor")testi 
    print(f"Qosulma: {DSN}\n")

    with psycopg.connect(DSN) as conn:
        with conn.cursor() as cur:
            for dovr in range(5):
                for s in sensorlar:
                    o = s.oxu()
                    cur.execute(
                        """INSERT INTO olcme (cihaz_kod, olcme_vaxti, qiymet)
                           VALUES (%s, %s, %s)""",
                        (o.cihaz_kod, o.olcme_vaxti, o.qiymet),
                    )
                conn.commit()
                print(f"Dovr {dovr+1}/5 yazildi (5 olcme)")
                time.sleep(1)

    print("\nBitdi. Yoxlamaq ucun:")
    print("  psql -p 5434 -U royatalibova -d zavod_edge_db \\")
    print("    -c \"SELECT count(*) FROM olcme;\"")


if __name__ == "__main__":
    main()
