-- zavod_maliyye: tam yeni sxem — faktura, odenis, bank_herekat, emek_haqqi

CREATE SCHEMA IF NOT EXISTS zavod_maliyye;

-- ── Hesab-faktura ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS zavod_maliyye.faktura (
    id               BIGSERIAL PRIMARY KEY,
    novu             TEXT NOT NULL,
    nomre            TEXT,
    tarix            DATE NOT NULL DEFAULT CURRENT_DATE,
    qarsi_teref      TEXT NOT NULL,
    qarsi_teref_voen TEXT,
    mebleg_edvsiz    NUMERIC NOT NULL DEFAULT 0,
    edv              NUMERIC NOT NULL DEFAULT 0,
    mebleg_cemi      NUMERIC NOT NULL DEFAULT 0,
    status           TEXT NOT NULL DEFAULT 'odenilmeyib',
    sened_id         BIGINT REFERENCES zavod_sened.sened(id),
    qeyd             TEXT,
    yaradilma        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT faktura_novu_yoxla CHECK (novu IN ('ALIS','SATIS')),
    CONSTRAINT faktura_status_yoxla CHECK (
        status IN ('odenilmeyib','qismen','odenilib')
    ),
    CONSTRAINT faktura_mebleg_musbet CHECK (mebleg_cemi >= 0)
);

CREATE INDEX IF NOT EXISTS idx_zm_faktura_tarix
    ON zavod_maliyye.faktura (tarix DESC);
CREATE INDEX IF NOT EXISTS idx_zm_faktura_status
    ON zavod_maliyye.faktura (status)
    WHERE status <> 'odenilib';
CREATE INDEX IF NOT EXISTS idx_zm_faktura_teref
    ON zavod_maliyye.faktura (qarsi_teref);

-- ── Odenis tapsirighi / kocurme ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS zavod_maliyye.odenis (
    id           BIGSERIAL PRIMARY KEY,
    faktura_id   BIGINT REFERENCES zavod_maliyye.faktura(id),
    novu         TEXT NOT NULL,
    mebleg       NUMERIC NOT NULL,
    tarix        DATE NOT NULL DEFAULT CURRENT_DATE,
    bank         TEXT,
    hesab_nomre  TEXT,
    tesvir       TEXT,
    yaradilma    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT odenis_novu_yoxla CHECK (
        novu IN ('KOCURME','NAGD','KASSA_MEDAXIL','KASSA_MEXARIC')
    ),
    CONSTRAINT odenis_mebleg_musbet CHECK (mebleg > 0)
);

CREATE INDEX IF NOT EXISTS idx_zm_odenis_faktura
    ON zavod_maliyye.odenis (faktura_id)
    WHERE faktura_id IS NOT NULL;

-- ── Bank cixarisi satirlari ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS zavod_maliyye.bank_herekat (
    id           BIGSERIAL PRIMARY KEY,
    tarix        DATE NOT NULL,
    bank         TEXT NOT NULL,
    novu         TEXT NOT NULL,
    mebleg       NUMERIC NOT NULL,
    qarsi_teref  TEXT,
    tesvir       TEXT,
    faktura_id   BIGINT REFERENCES zavod_maliyye.faktura(id),
    yukleme_vaxti TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT bank_herekat_novu_yoxla CHECK (novu IN ('MEDAXIL','MEXARIC')),
    CONSTRAINT bank_herekat_mebleg_musbet CHECK (mebleg > 0)
);

CREATE INDEX IF NOT EXISTS idx_zm_bank_tarix
    ON zavod_maliyye.bank_herekat (tarix DESC);

-- ── Emek haqqi (aylik, anonim) ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS zavod_maliyye.emek_haqqi (
    id            BIGSERIAL PRIMARY KEY,
    dovr          DATE NOT NULL,
    vezife        TEXT NOT NULL,
    ishci_kod     TEXT NOT NULL,
    ish_saati     NUMERIC NOT NULL DEFAULT 0,
    mebleg_brutto NUMERIC NOT NULL DEFAULT 0,
    mebleg_netto  NUMERIC NOT NULL DEFAULT 0,
    CONSTRAINT emek_haqqi_dovr_aylik CHECK (
        EXTRACT(DAY FROM dovr) = 1
    ),
    CONSTRAINT emek_haqqi_tek UNIQUE (dovr, ishci_kod)
);

-- ── Debitor / Kreditor balans view ────────────────────────────────────────────
CREATE OR REPLACE VIEW zavod_maliyye.debitor_kreditor AS
SELECT
    f.qarsi_teref,
    count(DISTINCT f.id)                                          AS faktura_sayi,
    COALESCE(sum(f.mebleg_cemi), 0)                               AS cemi_faktura,
    COALESCE(sum(o.mebleg), 0)                                    AS cemi_odenis,
    COALESCE(sum(f.mebleg_cemi), 0) - COALESCE(sum(o.mebleg), 0) AS qaliq_borc
FROM zavod_maliyye.faktura f
LEFT JOIN zavod_maliyye.odenis o ON o.faktura_id = f.id
GROUP BY f.qarsi_teref
ORDER BY qaliq_borc DESC;

DO $$ BEGIN
    RAISE NOTICE '14_maliyye.sql: faktura, odenis, bank_herekat, emek_haqqi + debitor_kreditor view hazirdir';
END $$;
