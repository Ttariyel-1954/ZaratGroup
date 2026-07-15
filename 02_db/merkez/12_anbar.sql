-- zavod_anbar: material cedveline erp_kod sutunu elave edilir
-- Movcud: material, herekat, qaliq (view), erp_kopru (hamisi SAXLANIR)

ALTER TABLE zavod_anbar.material
    ADD COLUMN IF NOT EXISTS erp_kod TEXT;

COMMENT ON COLUMN zavod_anbar.material.erp_kod IS
    'ERP inventory.products ile kopru - gelecek uzlasma ucun';

DO $$ BEGIN
    RAISE NOTICE '12_anbar.sql: erp_kod sutunu material cedveline elave edildi';
END $$;
