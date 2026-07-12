-- ============================================================
-- Dərs 06-A: Debouncing-i BAZADA məcburi et
-- SIRA: 3-cü — dublikat OLMAMALIDIR!
-- ============================================================

-- Bir cihaz + bir növ üçün YALNIZ BİR aktiv alert.
-- WHERE onu "qismən" edir: bağlanmışlar sərbəstdir (tarixçə).
CREATE UNIQUE INDEX IF NOT EXISTS xeberdarliq_aktiv_unikal
    ON xeberdarliq (cihaz_kod, novu)
    WHERE hell_olundu = FALSE;

-- Aktiv alertləri açılma vaxtına görə sürətli oxumaq üçün
CREATE INDEX IF NOT EXISTS idx_xeber_aktiv_acilma
    ON xeberdarliq (acilma_vaxti DESC)
    WHERE hell_olundu = FALSE;
