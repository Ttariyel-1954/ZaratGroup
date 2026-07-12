"""Baza qatı — bağlantı hovuzu və SQL əməliyyatları."""
from psycopg_pool import AsyncConnectionPool
from .konfiq import EDGE_DSN

hovuz = AsyncConnectionPool(
    conninfo=EDGE_DSN,
    min_size=2,
    max_size=10,
    open=False,
    timeout=10,
    max_lifetime=3600,
)

HEDLER: dict[str, dict] = {}


async def hedleri_yukle() -> int:
    """Cihaz hedleri VE alert parametrleri. Berpa/kritik hedler BURADA hesablanir."""
    sql = """
        SELECT c.kod, t.kod AS tip, t.vahid,
               t.min_hedd, t.max_hedd,
               t.ardicil_hedd, t.hysteresis_faiz, t.kritik_faiz
        FROM cihaz c
        JOIN sensor_tipi t ON c.sensor_tipi_kod = t.kod
        WHERE c.status = 'aktiv'
    """
    async with hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(sql)
            setirler = await cur.fetchall()

    HEDLER.clear()
    for (kod, tip, vahid, mn, mx, ardicil, hyst_faiz, kritik_faiz) in setirler:
        mn, mx = float(mn), float(mx)
        diapazon = mx - mn
        hyst = float(hyst_faiz) / 100
        krit = float(kritik_faiz) / 100

        HEDLER[kod] = {
            "tip": tip,
            "vahid": vahid,
            "min": mn,
            "max": mx,
            # Hysteresis: alert BU deyerlerde baglanir
            "berpa_yuxari": mx - diapazon * hyst,
            "berpa_asagi":  mn + diapazon * hyst,
            # Kritik: bu deyerlerden sonra seviyye = "kritik"
            "kritik_yuxari": mx * (1 + krit),
            "kritik_asagi":  mn * (1 - krit) if mn > 0 else mn * (1 + krit),
            "ardicil_hedd": int(ardicil),
        }

    return len(HEDLER)


async def olcme_yaz(kod: str, vaxt, qiymet: float) -> dict:
    mn, mx, vahid = HEDLER[kod]
    keyfiyyet = 1 if mn <= qiymet <= mx else 0
    xeber_mesaji = None

    async with hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """INSERT INTO olcme (cihaz_kod, olcme_vaxti, qiymet, keyfiyyet)
                   VALUES (%s, %s, %s, %s)""",
                (kod, vaxt, qiymet, keyfiyyet),
            )
            if qiymet > mx:
                xeber_mesaji = f"{kod}: {qiymet} {vahid} > maks {mx}"
                await cur.execute(
                    """INSERT INTO xeberdarliq
                       (cihaz_kod, olcme_vaxti, qiymet, novu, mesaj)
                       VALUES (%s, %s, %s, 'yuxari_hedd', %s)""",
                    (kod, vaxt, qiymet, xeber_mesaji),
                )
            elif qiymet < mn:
                xeber_mesaji = f"{kod}: {qiymet} {vahid} < min {mn}"
                await cur.execute(
                    """INSERT INTO xeberdarliq
                       (cihaz_kod, olcme_vaxti, qiymet, novu, mesaj)
                       VALUES (%s, %s, %s, 'asagi_hedd', %s)""",
                    (kod, vaxt, qiymet, xeber_mesaji),
                )

    return {"keyfiyyet": keyfiyyet, "xeberdarliq": xeber_mesaji}


async def son_olcmeler(limit: int = 20, cihaz: str | None = None) -> list:
    sql = """
        SELECT cihaz_kod, olcme_vaxti, qiymet, keyfiyyet, sync_status
        FROM olcme
        WHERE (%s::text IS NULL OR cihaz_kod = %s)
        ORDER BY olcme_vaxti DESC
        LIMIT %s
    """
    async with hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(sql, (cihaz, cihaz, limit))
            setirler = await cur.fetchall()
    return [
        {"cihaz_kod": r[0], "olcme_vaxti": r[1], "qiymet": float(r[2]),
         "keyfiyyet": r[3], "sync_status": r[4]}
        for r in setirler
    ]


async def cihazlar() -> list:
    sql = """
        SELECT c.kod, c.ad, t.ad, t.vahid, t.min_hedd, t.max_hedd, c.status
        FROM cihaz c JOIN sensor_tipi t ON c.sensor_tipi_kod = t.kod
        ORDER BY c.kod
    """
    async with hovuz.connection() as conn:
        async with conn.cursor() as cur:
            await cur.execute(sql)
            setirler = await cur.fetchall()
    return [
        {"kod": r[0], "ad": r[1], "tip": r[2], "vahid": r[3],
         "min_hedd": float(r[4]), "max_hedd": float(r[5]), "status": r[6]}
        for r in setirler
    ]
