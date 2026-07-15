-- zavod_istehsal: resept cedveline cixis_mehsul sutunu elave edilir
-- Movcud: resept (baza_miqdar=cixis_miqdar), resept_terkib, sifaris, sapma (view)
-- Not: faktiki_serf ayrı cedvel yox, herekat.sifaris_id vasitesile izlenir

ALTER TABLE zavod_istehsal.resept
    ADD COLUMN IF NOT EXISTS cixis_mehsul TEXT;

DO $$ BEGIN
    RAISE NOTICE '13_istehsal.sql: cixis_mehsul sutunu resept cedveline elave edildi';
END $$;
