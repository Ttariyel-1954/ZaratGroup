"""
Iki ayri baglanti hovuzu.
Edge   - HEMISE elcatan olmalidir.
Merkez - kesile biler, ve bu NORMALDIR.
"""
import logging

from psycopg_pool import AsyncConnectionPool

from .konfiq import EDGE_DSN, MERKEZ_DSN

log = logging.getLogger("sync.baza")

edge_hovuz = AsyncConnectionPool(
    conninfo=EDGE_DSN,
    min_size=1, max_size=3,
    open=False,
)

# min_size=0 VE wait() YOXDUR - merkez sonulu olsa da servis qalxir
merkez_hovuz = AsyncConnectionPool(
    conninfo=MERKEZ_DSN,
    min_size=0,
    max_size=3,
    timeout=10.0,
    open=False,
)


async def ac():
    await edge_hovuz.open()
    await edge_hovuz.wait()
    log.info("Edge hovuzu aciq")

    await merkez_hovuz.open()
    log.info("Merkez hovuzu aciq (elcatanliq yoxlanmadi)")


async def bagla():
    await edge_hovuz.close()
    await merkez_hovuz.close()


async def merkez_elcatandir() -> bool:
    """Merkez cavab verirmi? Istisna ATMIR."""
    try:
        async with merkez_hovuz.connection(timeout=5.0) as conn:
            async with conn.cursor() as cur:
                await cur.execute("SELECT 1")
        return True
    except Exception:
        return False
