-- Seed: zavod_istehsal
-- 4 resept, terkib, 6 sifaris, mexaric herekatlar (sapma gostermek ucun)

-- ── Reseptler ─────────────────────────────────────────────────────────────────
INSERT INTO zavod_istehsal.resept
    (kod, ad, cixis_mehsul, mehsul_vahid, baza_miqdar, versiya, aktiv)
VALUES
    ('YEM_BROYLER_START','Broyler Start Yemi (0-21 gun)',
     'Broyler Start', 'kq', 1000, 1, true),
    ('YEM_BROYLER_FINAL','Broyler Final Yemi (22-42 gun)',
     'Broyler Final', 'kq', 1000, 1, true),
    ('YEM_DAVAR',        'Davar (qoyun-keci) Yemi',
     'Davar Yemi',    'kq', 1000, 1, true),
    ('YEM_TOYUQ',        'Yumurtaci Toyuq Yemi',
     'Toyuq Yemi',    'kq', 1000, 1, true)
ON CONFLICT (kod) DO NOTHING;

-- ── Resept terkibi ────────────────────────────────────────────────────────────
-- YEM_BROYLER_START: 1000 kq ucun
INSERT INTO zavod_istehsal.resept_terkib
    (resept_kod, material_kod, miqdar, dozum_faiz)
VALUES
    ('YEM_BROYLER_START','QARGIDALI', 540, 2.0),
    ('YEM_BROYLER_START','SOYA_UNU',  280, 2.0),
    ('YEM_BROYLER_START','BALIQ_UNU', 80,  3.0),
    ('YEM_BROYLER_START','PREMIKS',   10,  5.0),
    ('YEM_BROYLER_START','YAG',       60,  3.0),
    ('YEM_BROYLER_START','DUZ',       5,   5.0),
    ('YEM_BROYLER_START','MEDDE_UNU', 15,  4.0),
    ('YEM_BROYLER_START','FOSFOR',    10,  5.0)
ON CONFLICT (resept_kod, material_kod) DO NOTHING;

-- YEM_BROYLER_FINAL: 1000 kq ucun
INSERT INTO zavod_istehsal.resept_terkib
    (resept_kod, material_kod, miqdar, dozum_faiz)
VALUES
    ('YEM_BROYLER_FINAL','QARGIDALI', 590, 2.0),
    ('YEM_BROYLER_FINAL','SOYA_UNU',  240, 2.0),
    ('YEM_BROYLER_FINAL','BALIQ_UNU', 60,  3.0),
    ('YEM_BROYLER_FINAL','PREMIKS',   10,  5.0),
    ('YEM_BROYLER_FINAL','YAG',       70,  3.0),
    ('YEM_BROYLER_FINAL','DUZ',       5,   5.0),
    ('YEM_BROYLER_FINAL','FOSFOR',    15,  5.0),
    ('YEM_BROYLER_FINAL','LIFLER',    10,  5.0)
ON CONFLICT (resept_kod, material_kod) DO NOTHING;

-- YEM_DAVAR: 1000 kq ucun
INSERT INTO zavod_istehsal.resept_terkib
    (resept_kod, material_kod, miqdar, dozum_faiz)
VALUES
    ('YEM_DAVAR','BUGDA',     450, 2.0),
    ('YEM_DAVAR','QARGIDALI', 300, 2.0),
    ('YEM_DAVAR','SOYA_UNU',  150, 2.0),
    ('YEM_DAVAR','PREMIKS',   8,   5.0),
    ('YEM_DAVAR','DUZ',       5,   5.0),
    ('YEM_DAVAR','LIFLER',    40,  4.0),
    ('YEM_DAVAR','FOSFOR',    10,  5.0)
ON CONFLICT (resept_kod, material_kod) DO NOTHING;

-- YEM_TOYUQ: 1000 kq ucun
INSERT INTO zavod_istehsal.resept_terkib
    (resept_kod, material_kod, miqdar, dozum_faiz)
VALUES
    ('YEM_TOYUQ','QARGIDALI', 500, 2.0),
    ('YEM_TOYUQ','SOYA_UNU',  250, 2.0),
    ('YEM_TOYUQ','BUGDA',     150, 2.0),
    ('YEM_TOYUQ','PREMIKS',   12,  5.0),
    ('YEM_TOYUQ','DUZ',       5,   5.0),
    ('YEM_TOYUQ','YAG',       50,  3.0),
    ('YEM_TOYUQ','MEDDE_UNU', 20,  4.0),
    ('YEM_TOYUQ','FOSFOR',    13,  5.0)
ON CONFLICT (resept_kod, material_kod) DO NOTHING;

-- ── Sifarisler ────────────────────────────────────────────────────────────────
INSERT INTO zavod_istehsal.sifaris
    (resept_kod, planlanan_miqdar, faktiki_miqdar, partiya_no, status, baslama, bitme)
VALUES
    ('YEM_BROYLER_START', 5000, 5000, 'P-2026-041',
     'bitdi', now()-INTERVAL '35 days', now()-INTERVAL '34 days'),
    ('YEM_BROYLER_FINAL', 4000, 4050, 'P-2026-042',
     'bitdi', now()-INTERVAL '28 days', now()-INTERVAL '27 days'),
    ('YEM_DAVAR',         3000, 2980, 'P-2026-043',
     'bitdi', now()-INTERVAL '21 days', now()-INTERVAL '20 days'),
    ('YEM_TOYUQ',         6000, 6000, 'P-2026-044',
     'bitdi', now()-INTERVAL '14 days', now()-INTERVAL '12 days'),
    ('YEM_BROYLER_START', 8000, NULL, 'P-2026-045',
     'isleyir', now()-INTERVAL '2 days', NULL),
    ('YEM_BROYLER_FINAL', 5000, NULL, 'P-2026-046',
     'planlanib', NULL, NULL)
ON CONFLICT (partiya_no) DO NOTHING;

-- ── Mexaric herekatlar sifarisler ucun (sapma hesabi) ────────────────────────
-- P-2026-041: 5000 kq broyler start (normadan bir-iki sapma olacaq)
WITH s AS (SELECT id FROM zavod_istehsal.sifaris WHERE partiya_no='P-2026-041')
INSERT INTO zavod_anbar.herekat
    (material_kod, novu, miqdar, menbe, sifaris_id, vaxt, qeyd)
SELECT v.material_kod, 'MEXARIC', v.miqdar, 'AI_TESDIQ', s.id,
       now()-INTERVAL '34 days', 'P-2026-041 istehsal serfi'
FROM (VALUES
    ('QARGIDALI', 2750::numeric),  -- gozlenilen: 540/1000*5000=2700 -- ARTIQ_SERF
    ('SOYA_UNU',  1380::numeric),  -- gozlenilen: 280/1000*5000=1400 -- AZ_SERF
    ('BALIQ_UNU',  400::numeric),  -- gozlenilen: 80/1000*5000=400   -- NORMA
    ('PREMIKS',     50::numeric),  -- gozlenilen: 10/1000*5000=50    -- NORMA
    ('YAG',        300::numeric),  -- gozlenilen: 60/1000*5000=300   -- NORMA
    ('DUZ',         25::numeric),  -- gozlenilen: 5/1000*5000=25     -- NORMA
    ('MEDDE_UNU',   80::numeric),  -- gozlenilen: 15/1000*5000=75    -- ARTIQ_SERF
    ('FOSFOR',      50::numeric)   -- gozlenilen: 10/1000*5000=50    -- NORMA
) AS v(material_kod, miqdar)
CROSS JOIN s
ON CONFLICT DO NOTHING;

-- P-2026-042: 4050 kq broyler final (faktiki_miqdar=4050)
WITH s AS (SELECT id FROM zavod_istehsal.sifaris WHERE partiya_no='P-2026-042')
INSERT INTO zavod_anbar.herekat
    (material_kod, novu, miqdar, menbe, sifaris_id, vaxt, qeyd)
SELECT v.material_kod, 'MEXARIC', v.miqdar, 'AI_TESDIQ', s.id,
       now()-INTERVAL '27 days', 'P-2026-042 istehsal serfi'
FROM (VALUES
    ('QARGIDALI', 2390::numeric),  -- gozlenilen: 590/1000*4050=2389.5 -- NORMA
    ('SOYA_UNU',  970::numeric),   -- gozlenilen: 240/1000*4050=972    -- NORMA
    ('BALIQ_UNU', 245::numeric),   -- gozlenilen: 60/1000*4050=243     -- NORMA
    ('PREMIKS',    41::numeric),   -- gozlenilen: 10/1000*4050=40.5    -- NORMA
    ('YAG',       300::numeric),   -- gozlenilen: 70/1000*4050=283.5   -- ARTIQ_SERF
    ('DUZ',        20::numeric),   -- gozlenilen: 5/1000*4050=20.25    -- NORMA
    ('FOSFOR',     62::numeric),   -- gozlenilen: 15/1000*4050=60.75   -- NORMA
    ('LIFLER',     38::numeric)    -- gozlenilen: 10/1000*4050=40.5    -- AZ_SERF
) AS v(material_kod, miqdar)
CROSS JOIN s
ON CONFLICT DO NOTHING;

-- P-2026-043: 2980 kq davar
WITH s AS (SELECT id FROM zavod_istehsal.sifaris WHERE partiya_no='P-2026-043')
INSERT INTO zavod_anbar.herekat
    (material_kod, novu, miqdar, menbe, sifaris_id, vaxt, qeyd)
SELECT v.material_kod, 'MEXARIC', v.miqdar, 'AI_TESDIQ', s.id,
       now()-INTERVAL '20 days', 'P-2026-043 istehsal serfi'
FROM (VALUES
    ('BUGDA',     1341::numeric),  -- gozlenilen: 450/1000*2980=1341 -- NORMA
    ('QARGIDALI',  900::numeric),  -- gozlenilen: 300/1000*2980=894  -- ARTIQ_SERF
    ('SOYA_UNU',   447::numeric),  -- gozlenilen: 150/1000*2980=447  -- NORMA
    ('PREMIKS',     24::numeric),  -- gozlenilen: 8/1000*2980=23.84  -- NORMA
    ('DUZ',         15::numeric),  -- gozlenilen: 5/1000*2980=14.9   -- NORMA
    ('LIFLER',     120::numeric),  -- gozlenilen: 40/1000*2980=119.2 -- NORMA
    ('FOSFOR',      28::numeric)   -- gozlenilen: 10/1000*2980=29.8  -- AZ_SERF
) AS v(material_kod, miqdar)
CROSS JOIN s
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_r INT; v_rt INT; v_s INT; v_h INT;
BEGIN
    SELECT count(*) INTO v_r  FROM zavod_istehsal.resept;
    SELECT count(*) INTO v_rt FROM zavod_istehsal.resept_terkib;
    SELECT count(*) INTO v_s  FROM zavod_istehsal.sifaris;
    SELECT count(*) INTO v_h  FROM zavod_anbar.herekat WHERE sifaris_id IS NOT NULL;
    RAISE NOTICE '23_seed_istehsal: % resept | % terkib | % sifaris | % mexaric-herekat',
        v_r, v_rt, v_s, v_h;
END $$;
