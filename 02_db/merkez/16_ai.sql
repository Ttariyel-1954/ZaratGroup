-- zavod_ai: movcud struktur tam komplektdir — yalniz yoxlama
-- Movcud: cixaris, qerar, jurnal, gunluk_xerc (view), deqiqlik (view)

DO $$
DECLARE
    v_cedvel_say INT;
    v_view_say   INT;
BEGIN
    SELECT count(*) INTO v_cedvel_say
    FROM information_schema.tables
    WHERE table_schema = 'zavod_ai'
      AND table_type = 'BASE TABLE';

    SELECT count(*) INTO v_view_say
    FROM information_schema.views
    WHERE table_schema = 'zavod_ai';

    RAISE NOTICE '16_ai.sql: zavod_ai sxeminde % cedvel, % view -- yoxlama kecdi',
        v_cedvel_say, v_view_say;

    IF v_cedvel_say < 3 THEN
        RAISE EXCEPTION 'zavod_ai sxeminde cedvel catishmayir!';
    END IF;
END $$;
