-- ============================================================
-- Dərs 07-A: Mərkəzi sinxronizasiya — EDGE tərəfi
-- Tarix: 2026-07-12
-- İşlədilir: psql -p 5434 -d zavod_edge_db -f 02_db/edge/08_sync_sxem.sql
-- ============================================================

-- 1. xeberdarliq-a sync bayrağı
ALTER TABLE xeberdarliq
    ADD COLUMN IF NOT EXISTS sync_status SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS sync_vaxti  TIMESTAMPTZ;

-- 2. Göndəriləcəkləri sürətlə tapmaq üçün QİSMƏN indeks
--    Yalnız sync_status=0 olan sətirləri əhatə edir — kiçik və sürətli
CREATE INDEX IF NOT EXISTS idx_xeber_sync
    ON xeberdarliq (id)
    WHERE sync_status = 0;

-- 3. TRIGGER: alert DƏYİŞƏNDƏ bayrağı SIFIRLA
--    Cunki alert yasayir - tetik_sayi artir, seviyye yukselir,
--    hell_olundu deyisir. Her deyisiklik merkeze catmalidir.
CREATE OR REPLACE FUNCTION xeber_sync_sifirla()
RETURNS TRIGGER AS $$
BEGIN
    NEW.sync_status := 0;
    NEW.sync_vaxti  := NULL;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_xeber_sync ON xeberdarliq;

CREATE TRIGGER trg_xeber_sync
    BEFORE UPDATE ON xeberdarliq
    FOR EACH ROW
    WHEN (
        OLD.tetik_sayi   IS DISTINCT FROM NEW.tetik_sayi   OR
        OLD.seviyye      IS DISTINCT FROM NEW.seviyye      OR
        OLD.hell_olundu  IS DISTINCT FROM NEW.hell_olundu  OR
        OLD.pik_qiymet   IS DISTINCT FROM NEW.pik_qiymet
    )
    EXECUTE FUNCTION xeber_sync_sifirla();

-- 4. Sync metrikaları üçün görünüş (view)
CREATE OR REPLACE VIEW sync_veziyyet AS
SELECT
    'olcme' AS cedvel,
    count(*) FILTER (WHERE sync_status = 0) AS gozleyen,
    count(*) FILTER (WHERE sync_status = 1) AS gonderilen,
    min(olcme_vaxti) FILTER (WHERE sync_status = 0) AS en_kohne_gozleyen
FROM olcme
UNION ALL
SELECT
    'xeberdarliq',
    count(*) FILTER (WHERE sync_status = 0),
    count(*) FILTER (WHERE sync_status = 1),
    min(acilma_vaxti) FILTER (WHERE sync_status = 0)
FROM xeberdarliq;

SELECT * FROM sync_veziyyet;
