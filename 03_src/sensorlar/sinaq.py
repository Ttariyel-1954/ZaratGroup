"""
Simulyator sinaq skripti — ekranda canli siqnal gosterir.
Fayl: 03_src/sensorlar/sinaq.py
Ishe salmaq:  python sinaq.py
Dayandirmaq:  CTRL+C
"""
import time
from sensorlar import butun_sensorlar


def main():
    sensorlar = butun_sensorlar()
    print("Zarat Faza 2 — Sensor simulyatoru (sinaq)")
    print("Dayandirmaq ucun CTRL+C basin\n")
    print(f"{'cihaz':<8}{'qiymet':>12}   {'vaxt (UTC)'}")
    print("-" * 52)

    try:
        while True:
            for s in sensorlar:
                o = s.oxu()
                print(f"{o.cihaz_kod:<8}{o.qiymet:>12.3f}   {o.olcme_vaxti}")
            print("-" * 52)
            time.sleep(2)
    except KeyboardInterrupt:
        print("\nSimulyator dayandirildi.")


if __name__ == "__main__":
    main()
