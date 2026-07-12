-- ============================================================
-- Dərs 06-A: Alert vəziyyət maşını — SXEM
-- SIRA: 1-ci (indeks YOX — o, 07-dədir)
-- ============================================================

-- 1. Yeni sütunlar
ALTER TABLE xeberdarliq
    ADD COLUMN IF NOT EXISTS seviyye        VARCHAR(15)  NOT NULL DEFAULT 'xeberdarliq',
    ADD COLUMN IF NOT EXISTS acilma_vaxti   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS baglanma_vaxti TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS tetik_sayi     INTEGER      NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS ilk_qiymet     NUMERIC(12,4),
    ADD COLUMN IF NOT EXISTS son_qiymet     NUMERIC(12,4),
    ADD COLUMN IF NOT EXISTS pik_qiymet     NUMERIC(12,4);

-- 2. Səviyyə yalnız iki dəyər
ALTER TABLE xeberdarliq DROP CONSTRAINT IF EXISTS xeberdarliq_seviyye_chk;
ALTER TABLE xeberdarliq
    ADD CONSTRAINT xeberdarliq_seviyye_chk
    CHECK (seviyye IN ('xeberdarliq', 'kritik'));

-- 3. Bağlanma vaxtı yalnız həll olunmuş alertdə
ALTER TABLE xeberdarliq DROP CONSTRAINT IF EXISTS xeberdarliq_baglanma_chk;
ALTER TABLE xeberdarliq
    ADD CONSTRAINT xeberdarliq_baglanma_chk
    CHECK (
        (hell_olundu = TRUE  AND baglanma_vaxti IS NOT NULL) OR
        (hell_olundu = FALSE AND baglanma_vaxti IS NULL)
    );

-- 4. sensor_tipi-yə alert parametrləri
ALTER TABLE sensor_tipi
    ADD COLUMN IF NOT EXISTS ardicil_hedd    SMALLINT     NOT NULL DEFAULT 3,
    ADD COLUMN IF NOT EXISTS hysteresis_faiz NUMERIC(5,2) NOT NULL DEFAULT 5.0,
    ADD COLUMN IF NOT EXISTS kritik_faiz     NUMERIC(5,2) NOT NULL DEFAULT 20.0;

-- 5. Tiplərə uyğun dəyərlər
UPDATE sensor_tipi SET ardicil_hedd = 2, kritik_faiz = 15.0    WHERE kod = 'VIBRASIYA';
UPDATE sensor_tipi SET ardicil_hedd = 5, hysteresis_faiz = 6.0 WHERE kod = 'TEMP';
UPDATE sensor_tipi SET ardicil_hedd = 3, hysteresis_faiz = 8.0 WHERE kod = 'CEKI';
UPDATE sensor_tipi SET ardicil_hedd = 4                        WHERE kod = 'ENERJI';

SELECT kod, min_hedd, max_hedd, vahid,
       ardicil_hedd, hysteresis_faiz, kritik_faiz
FROM sensor_tipi ORDER BY kod;
