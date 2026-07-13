-- ============================================================
-- Faza 3: Edge sənəd sxemi
-- İşlədilir:
--   psql -p 5434 -d zavod_edge_db -f 02_db/edge/09_sened_sxem.sql
-- ============================================================

-- ============================================================
-- SƏNƏD — zavodda yaranan/qəbul edilən hər sənəd
-- ============================================================
CREATE TABLE IF NOT EXISTS sened (
    id              BIGSERIAL PRIMARY KEY,
    -- Sənədin növü
    novu            TEXT NOT NULL,
    -- Zavodun daxili nömrəsi (varsa)
    nomre           TEXT,
    -- Sənədin öz tarixi (qaimənin üstündəki tarix)
    sened_tarixi    DATE,
    -- Qarşı tərəf: təchizatçı / müştəri adı
    qarsi_teref     TEXT,
    -- Sərbəst mətn qeyd
    qeyd            TEXT,
    -- Kim daxil etdi
    daxil_eden      TEXT NOT NULL,
    -- Necə daxil oldu: FORM, FAYL, SEKIL, EPOCT, EXCEL
    menbe           TEXT NOT NULL DEFAULT 'FAYL',
    -- Status: qaralama, tesdiq_gozleyir, tesdiqlendi, redd_edildi, legv
    status          TEXT NOT NULL DEFAULT 'qaralama',
    -- Struktur məlumat (AI çıxarışı və ya formdan)
    metadata        JSONB DEFAULT '{}'::jsonb,

    yaradilma_vaxti TIMESTAMPTZ NOT NULL DEFAULT now(),
    deyisme_vaxti   TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- SYNC (Faza 2 nümunəsi ilə)
    sync_status     SMALLINT NOT NULL DEFAULT 0,   -- 0=novbede, 1=gonderildi
    sync_vaxti      TIMESTAMPTZ,

    CONSTRAINT sened_novu_yoxla CHECK (novu <> ''),
    CONSTRAINT sened_status_yoxla CHECK (status IN
        ('qaralama','tesdiq_gozleyir','tesdiqlendi','redd_edildi','legv'))
);

-- Göndərilməyənləri sürətlə tapmaq üçün qismən indeks
CREATE INDEX IF NOT EXISTS idx_sened_sync
    ON sened (id) WHERE sync_status = 0;

CREATE INDEX IF NOT EXISTS idx_sened_novu_tarix
    ON sened (novu, sened_tarixi DESC);

CREATE INDEX IF NOT EXISTS idx_sened_metadata
    ON sened USING GIN (metadata);

-- ============================================================
-- SƏNƏD FAYLI — PDF, şəkil, Excel, Word
-- FAYLIN ÖZÜ BAZADA DEYİL. Yalnız metadata + hash.
-- ============================================================
CREATE TABLE IF NOT EXISTS sened_fayl (
    id              BIGSERIAL PRIMARY KEY,
    sened_id        BIGINT NOT NULL REFERENCES sened(id) ON DELETE CASCADE,

    orijinal_ad     TEXT NOT NULL,
    mime_tipi       TEXT NOT NULL,
    olcu_bayt       BIGINT NOT NULL,

    -- MinIO-da obyektin açarı: "SIYEZEN/2026/07/13/<uuid>.pdf"
    obyekt_acari    TEXT NOT NULL UNIQUE,
    -- SHA-256 — tamliq yoxlamasi ucun. Merkezdə təkrar hesablanır.
    sha256          TEXT NOT NULL,

    yuklenme_vaxti  TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Fayl merkezi MinIO-ya kocurulubmu
    sync_status     SMALLINT NOT NULL DEFAULT 0,
    sync_vaxti      TIMESTAMPTZ,
    sync_cehd_sayi  INT NOT NULL DEFAULT 0,
    son_xeta        TEXT,

    CONSTRAINT fayl_sha_yoxla CHECK (length(sha256) = 64)
);

CREATE INDEX IF NOT EXISTS idx_fayl_sync
    ON sened_fayl (id) WHERE sync_status = 0;

CREATE INDEX IF NOT EXISTS idx_fayl_sened
    ON sened_fayl (sened_id);

-- Problemli fayllar: 3 dəfədən çox cəhd, hələ göndərilməyib
CREATE INDEX IF NOT EXISTS idx_fayl_problemli
    ON sened_fayl (sync_cehd_sayi) WHERE sync_status = 0 AND sync_cehd_sayi > 3;

-- ============================================================
-- TRIGGER — sənəd dəyişəndə sync_status sıfırlanır
-- Sonsuz dövrə DUSMEMEK ucun WHEN serti VACIBdIR.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_sened_sync_sifirla()
RETURNS TRIGGER AS $func$
BEGIN
    NEW.sync_status   := 0;
    NEW.sync_vaxti    := NULL;
    NEW.deyisme_vaxti := now();
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sened_sync ON sened;
CREATE TRIGGER trg_sened_sync
    BEFORE UPDATE ON sened
    FOR EACH ROW
    WHEN (OLD.status      IS DISTINCT FROM NEW.status
       OR OLD.metadata    IS DISTINCT FROM NEW.metadata
       OR OLD.nomre       IS DISTINCT FROM NEW.nomre
       OR OLD.qarsi_teref IS DISTINCT FROM NEW.qarsi_teref)
    EXECUTE FUNCTION fn_sened_sync_sifirla();

-- ============================================================
-- GORUNUS — sync veziyyeti
-- ============================================================
CREATE OR REPLACE VIEW sened_sync_veziyyet AS
SELECT
    (SELECT count(*) FROM sened      WHERE sync_status = 0) AS sened_novbede,
    (SELECT count(*) FROM sened_fayl WHERE sync_status = 0) AS fayl_novbede,
    (SELECT coalesce(sum(olcu_bayt), 0) FROM sened_fayl
       WHERE sync_status = 0)                                AS novbede_bayt,
    (SELECT count(*) FROM sened_fayl WHERE sync_cehd_sayi > 3
       AND sync_status = 0)                                  AS problemli_fayl;

-- Yoxlama
SELECT * FROM sened_sync_veziyyet;
