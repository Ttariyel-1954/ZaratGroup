-- ============================================================
-- Merkezi baza (zarat_erp_2) - telemetriya qebul cedveli
-- Fayl: 02_db/merkez/01_telemetriya.sql
-- ============================================================

-- ayrica sxem: movcud ERP cedvellerine toxunmuruq
CREATE SCHEMA IF NOT EXISTS zavod_telemetriya;

-- olcmelerin merkezi kopyasi
CREATE TABLE IF NOT EXISTS zavod_telemetriya.olcme (
    id              BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    zavod           VARCHAR(30)  NOT NULL DEFAULT 'siyezen',
    edge_id         BIGINT       NOT NULL,           -- zavod bazasindaki id
    cihaz_kod       VARCHAR(20)  NOT NULL,
    olcme_vaxti     TIMESTAMPTZ  NOT NULL,
    qiymet          NUMERIC(12,4) NOT NULL,
    qebul_vaxti     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- eyni olcme iki defe gelmesin (idempotentlik)
    UNIQUE (zavod, edge_id)
);

CREATE INDEX IF NOT EXISTS idx_tel_cihaz_vaxt
    ON zavod_telemetriya.olcme (cihaz_kod, olcme_vaxti DESC);

COMMENT ON TABLE zavod_telemetriya.olcme IS
    'Zavodlardan sinxronlasdirilan telemetriya olcmeleri';
COMMENT ON COLUMN zavod_telemetriya.olcme.edge_id IS
    'Zavod bazasindaki original id - tekrar gonderilmenin qarsisini alir';
