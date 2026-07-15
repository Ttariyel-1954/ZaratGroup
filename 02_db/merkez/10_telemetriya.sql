-- zavod_telemetriya: cihaz, xeberdarliq cedvelleri + cihaz_son_veziyyet view
-- Movcud: olcme (saxlanir, keyfiyyet sutunu elave edilir)
-- Yeni: cihaz, xeberdarliq, cihaz_son_veziyyet

CREATE SCHEMA IF NOT EXISTS zavod_telemetriya;

-- ── Sensor reyestri ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS zavod_telemetriya.cihaz (
    kod             TEXT PRIMARY KEY,
    ad              TEXT NOT NULL,
    tip             TEXT NOT NULL,
    vahid           TEXT NOT NULL,
    yer             TEXT,
    min_norma       NUMERIC,
    max_norma       NUMERIC,
    aktiv           BOOLEAN NOT NULL DEFAULT true,
    qurulma_tarixi  DATE,
    CONSTRAINT cihaz_tip_yoxla CHECK (
        tip IN ('TEMPERATUR','RUTUBET','CEKI','ENERJI','SURET','QAZ','SEVIYYE')
    )
);

-- ── Movcud olcme cedveline keyfiyyet sutunu ──────────────────────────────────
ALTER TABLE zavod_telemetriya.olcme
    ADD COLUMN IF NOT EXISTS keyfiyyet SMALLINT NOT NULL DEFAULT 1;

-- ── Xeberdarliq cedveli ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS zavod_telemetriya.xeberdarliq (
    id              BIGSERIAL PRIMARY KEY,
    cihaz_kod       TEXT NOT NULL REFERENCES zavod_telemetriya.cihaz(kod),
    novu            TEXT NOT NULL,
    seviyye         TEXT NOT NULL,
    qiymet          NUMERIC,
    mesaj           TEXT,
    yaranma_vaxti   TIMESTAMPTZ NOT NULL DEFAULT now(),
    hell_olunub     BOOLEAN NOT NULL DEFAULT false,
    hell_vaxti      TIMESTAMPTZ,
    CONSTRAINT xeberdarliq_novu_yoxla CHECK (
        novu IN ('HEDD_ASILDI','CIHAZ_SUSDU','ANOMAL')
    ),
    CONSTRAINT xeberdarliq_seviyye_yoxla CHECK (
        seviyye IN ('kritik','xeberdarliq','info')
    )
);

CREATE INDEX IF NOT EXISTS idx_zt_xeberdarliq_aktiv
    ON zavod_telemetriya.xeberdarliq (cihaz_kod, yaranma_vaxti DESC)
    WHERE NOT hell_olunub;

-- ── Her cihazin son olcmesi + norma muqayisesi ───────────────────────────────
CREATE OR REPLACE VIEW zavod_telemetriya.cihaz_son_veziyyet AS
SELECT
    c.kod,
    c.ad,
    c.tip,
    c.vahid,
    c.yer,
    c.min_norma,
    c.max_norma,
    c.aktiv,
    o.qiymet          AS son_qiymet,
    o.olcme_vaxti     AS son_vaxt,
    o.keyfiyyet,
    CASE
        WHEN o.qiymet IS NULL                                        THEN NULL
        WHEN c.min_norma IS NOT NULL AND o.qiymet < c.min_norma      THEN false
        WHEN c.max_norma IS NOT NULL AND o.qiymet > c.max_norma      THEN false
        ELSE true
    END AS norma_daxilinde
FROM zavod_telemetriya.cihaz c
LEFT JOIN LATERAL (
    SELECT qiymet, olcme_vaxti, keyfiyyet
    FROM   zavod_telemetriya.olcme
    WHERE  cihaz_kod = c.kod
    ORDER  BY olcme_vaxti DESC
    LIMIT  1
) o ON true;

DO $$ BEGIN
    RAISE NOTICE '10_telemetriya.sql: cihaz, xeberdarliq cedvelleri ve cihaz_son_veziyyet view hazirdir';
END $$;
