-- ============================================================
-- olcme cədvəli üçün aylıq partisiyalar
-- Fayl: 02_db/edge/02_partisiyalar.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS olcme_2026_07 PARTITION OF olcme
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE IF NOT EXISTS olcme_2026_08 PARTITION OF olcme
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE IF NOT EXISTS olcme_2026_09 PARTITION OF olcme
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');

-- DEFAULT partisiya: heç bir aralığa düşməyən sətirlər buraya gedir
CREATE TABLE IF NOT EXISTS olcme_default PARTITION OF olcme DEFAULT;

-- Verilən tarix üçün aylıq partisiya yaradan funksiya
CREATE OR REPLACE FUNCTION partisiya_yarat(p_tarix DATE)
RETURNS TEXT AS $$
DECLARE
    v_bas DATE := date_trunc('month', p_tarix)::DATE;
    v_son DATE := (date_trunc('month', p_tarix) + INTERVAL '1 month')::DATE;
    v_ad  TEXT := 'olcme_' || to_char(v_bas, 'YYYY_MM');
BEGIN
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF olcme
         FOR VALUES FROM (%L) TO (%L)',
        v_ad, v_bas, v_son
    );
    RETURN v_ad || ' yaradildi (' || v_bas || ' - ' || v_son || ')';
END;
$$ LANGUAGE plpgsql;

-- Nümunə: oktyabr partisiyasını yaradaq
SELECT partisiya_yarat('2026-10-15');
