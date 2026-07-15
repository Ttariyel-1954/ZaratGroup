-- zavod_sened: movcud cedvellere catishmayan sutunlar elave edilir
-- Movcud: sened, fayl, versiya, tesdiq, sync_jurnal (hamisi SAXLANIR)

-- ── sened cedveline elave sutunlar ───────────────────────────────────────────
ALTER TABLE zavod_sened.sened
    ADD COLUMN IF NOT EXISTS mebleg            NUMERIC,
    ADD COLUMN IF NOT EXISTS qarsi_teref_voen  TEXT;

-- ── INDEX: maliyye sorgulari ucun ────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_zs_sened_mebleg
    ON zavod_sened.sened (sened_tarixi DESC)
    WHERE mebleg IS NOT NULL;

DO $$ BEGIN
    RAISE NOTICE '11_sened.sql: mebleg ve qarsi_teref_voen sutunlari elave edildi';
END $$;
