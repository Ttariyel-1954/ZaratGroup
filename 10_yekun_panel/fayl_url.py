#!/usr/bin/env python3
# ==============================================================================
# fayl_url.py — MinIO obyekti üçün müvəqqəti (presigned) URL qaytarır
# ==============================================================================
#
#   İşlədilməsi (R və ya terminal):
#     python3 fayl_url.py "SIYEZEN/2026/07/13/uuid.pdf"
#
#   Çıxış (stdout, tək sətir):
#     OK<TAB>http://localhost:9000/zarat-sened/...?X-Amz-Signature=...
#   və ya:
#     XETA<TAB>səbəb
#
#   Konfiqurasiya .env-dən oxunur (01_config/.env).
# ==============================================================================

import sys, os

def env_oxu(yol):
    d = {}
    if not os.path.exists(yol):
        return d
    with open(yol, encoding="utf-8") as f:
        for s in f:
            s = s.strip()
            if not s or s.startswith("#") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            d[k.strip()] = v.strip()
    return d

def main():
    if len(sys.argv) < 2:
        print("XETA\tobyekt acari verilmedi")
        return

    acar = sys.argv[1]

    # .env tap
    kok = os.path.expanduser("~/Desktop/Zarat_Faza2_Zavod")
    env = env_oxu(os.path.join(kok, "01_config", ".env"))

    endpoint = env.get("MINIO_MERKEZ_URL", "http://localhost:9000")
    endpoint = endpoint.replace("http://", "").replace("https://", "")
    access = env.get("MINIO_ACCESS_KEY", "zarat_admin")
    secret = env.get("MINIO_SECRET_KEY", "Zarat2026Siyezen")
    bucket = env.get("MINIO_BUCKET", "zarat-sened")

    try:
        from minio import Minio
        from datetime import timedelta
    except ImportError:
        print("XETA\tminio kitabxanasi yoxdur (pip install minio)")
        return

    try:
        client = Minio(endpoint, access_key=access, secret_key=secret, secure=False)

        # obyekt mövcuddurmu?
        try:
            client.stat_object(bucket, acar)
        except Exception:
            print("XETA\tfayl MinIO-da tapilmadi (seed data ola biler)")
            return

        url = client.presigned_get_object(bucket, acar, expires=timedelta(minutes=15))
        print("OK\t" + url)
    except Exception as e:
        print("XETA\t" + str(e).replace("\n", " ")[:200])

if __name__ == "__main__":
    main()
