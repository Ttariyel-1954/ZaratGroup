-- Seed: zavod_anbar
-- 5 yeni material (movcud 5-e elave), 30+ herekat
-- PREMIKS: qesdən mənfi qaliq (demo üçün kritik qerar)

-- ── Materiallar ───────────────────────────────────────────────────────────────
INSERT INTO zavod_anbar.material
    (kod, ad, vahid, kateqoriya, min_qaliq, aktiv)
VALUES
    ('PREMIKS',      'Vitamin-mineral premiks', 'kq', 'KOMEKCI',      50,  true),
    ('YAG',          'Bitki yagi',              'litr','KOMEKCI',     100,  true),
    ('MEDDE_UNU',    'Medde unu (lizin)',       'kq', 'KOMEKCI',      30,  true),
    ('FOSFOR',       'Dikalsium fosfat',        'kq', 'KOMEKCI',      25,  true),
    ('LIFLER',       'Selluloza lifleri',       'kq', 'KOMEKCI',      20,  true)
ON CONFLICT (kod) DO NOTHING;

-- ── Herekatlar — mevcut 5 material ucun geçmiş hərəkatlər ────────────────────
-- QARGIDALI (mövcud: +2500 -3000 = -500) — artıq mənfi, əlavə mədaxil edək
INSERT INTO zavod_anbar.herekat
    (material_kod, novu, miqdar, vahid_qiymet, menbe, vaxt, qeyd)
VALUES
    ('QARGIDALI','MEDAXIL', 8000, 0.85,'AI_TESDIQ', now()-INTERVAL '85 days',
     'Aqro-Servis MMC tedariki'),
    ('QARGIDALI','MEDAXIL', 5000, 0.87,'AI_TESDIQ', now()-INTERVAL '55 days',
     'Xezri Ticarət ASC tedariki'),
    ('QARGIDALI','MEXARIC', 4500, NULL,'AI_TESDIQ', now()-INTERVAL '50 days',
     'Broyler start yemi istehsali'),
    ('QARGIDALI','MEXARIC', 3200, NULL,'AI_TESDIQ', now()-INTERVAL '40 days',
     'Davar yemi istehsali'),
    ('SOYA_UNU', 'MEDAXIL', 3000, 1.45,'AI_TESDIQ', now()-INTERVAL '80 days',
     'Soya-Tur MMC tedariki'),
    ('SOYA_UNU', 'MEDAXIL', 2500, 1.48,'AI_TESDIQ', now()-INTERVAL '50 days',
     'Soya-Tur MMC tedariki'),
    ('SOYA_UNU', 'MEXARIC', 2200, NULL,'AI_TESDIQ', now()-INTERVAL '45 days',
     'Broyler final yemi istehsali'),
    ('SOYA_UNU', 'MEXARIC', 1800, NULL,'AI_TESDIQ', now()-INTERVAL '30 days',
     'Toyuq yemi istehsali'),
    ('BUGDA',    'MEDAXIL', 6000, 0.62,'AI_TESDIQ', now()-INTERVAL '75 days',
     'Araz Taxil MMC tedariki'),
    ('BUGDA',    'MEDAXIL', 4000, 0.64,'AI_TESDIQ', now()-INTERVAL '45 days',
     'Araz Taxil MMC tedariki'),
    ('BUGDA',    'MEXARIC', 3500, NULL,'AI_TESDIQ', now()-INTERVAL '40 days',
     'Broyler yemi istehsali'),
    ('BUGDA',    'MEXARIC', 2800, NULL,'AI_TESDIQ', now()-INTERVAL '20 days',
     'Davar yemi istehsali'),
    ('BALIQ_UNU','MEDAXIL',  800, 3.20,'AI_TESDIQ', now()-INTERVAL '70 days',
     'Baliq-Un Az tedariki'),
    ('BALIQ_UNU','MEDAXIL',  600, 3.25,'AI_TESDIQ', now()-INTERVAL '35 days',
     'Baliq-Un Az tedariki'),
    ('BALIQ_UNU','MEXARIC',  450, NULL,'AI_TESDIQ', now()-INTERVAL '30 days',
     'Broyler final yemi istehsali'),
    ('DUZ',      'MEDAXIL',  500, 0.18,'AI_TESDIQ', now()-INTERVAL '90 days',
     'Respublika duzu tedariki'),
    ('DUZ',      'MEXARIC',  120, NULL,'AI_TESDIQ', now()-INTERVAL '60 days',
     'Yem istehsali'),
    ('DUZ',      'MEXARIC',   90, NULL,'AI_TESDIQ', now()-INTERVAL '30 days',
     'Yem istehsali')
ON CONFLICT DO NOTHING;

-- ── PREMIKS: QƏSDƏN mənfi qaliq (kritik demo) ────────────────────────────────
INSERT INTO zavod_anbar.herekat
    (material_kod, novu, miqdar, vahid_qiymet, menbe, vaxt, qeyd)
VALUES
    ('PREMIKS','MEDAXIL', 300, 8.50,'AI_TESDIQ', now()-INTERVAL '60 days',
     'Premiks tedariki'),
    ('PREMIKS','MEXARIC', 180, NULL,'AI_TESDIQ', now()-INTERVAL '45 days',
     'Broyler yemi istehsali'),
    ('PREMIKS','MEXARIC',  90, NULL,'AI_TESDIQ', now()-INTERVAL '30 days',
     'Davar yemi istehsali'),
    ('PREMIKS','MEXARIC', 180, NULL,'AI_TESDIQ', now()-INTERVAL '10 days',
     'Broyler final yemi -- qaliq yoxlanilmadi')
-- Qaliq: 300 - 180 - 90 - 180 = -150 (kritik!)
ON CONFLICT DO NOTHING;

-- ── Diger yeni materiallar ────────────────────────────────────────────────────
INSERT INTO zavod_anbar.herekat
    (material_kod, novu, miqdar, vahid_qiymet, menbe, vaxt, qeyd)
VALUES
    ('YAG',     'MEDAXIL', 500, 1.85,'AI_TESDIQ', now()-INTERVAL '50 days',
     'Bitki yagi tedariki'),
    ('YAG',     'MEXARIC', 220, NULL,'AI_TESDIQ', now()-INTERVAL '35 days',
     'Yem formulu'),
    ('MEDDE_UNU','MEDAXIL',200, 2.10,'AI_TESDIQ', now()-INTERVAL '55 days',
     'Lizin tedariki'),
    ('MEDDE_UNU','MEXARIC', 85, NULL,'AI_TESDIQ', now()-INTERVAL '40 days',
     'Broyler yemi'),
    ('FOSFOR',  'MEDAXIL', 150, 1.95,'AI_TESDIQ', now()-INTERVAL '65 days',
     'Dikalsium fosfat'),
    ('FOSFOR',  'MEXARIC',  60, NULL,'AI_TESDIQ', now()-INTERVAL '30 days',
     'Yem istehsali'),
    ('LIFLER',  'MEDAXIL', 120, 0.95,'AI_TESDIQ', now()-INTERVAL '70 days',
     'Selluloza tedariki'),
    ('LIFLER',  'MEXARIC',  40, NULL,'AI_TESDIQ', now()-INTERVAL '25 days',
     'Davar yemi')
ON CONFLICT DO NOTHING;

-- ── INVENTAR_DUZELIS: sened qaimesine baglanmis ───────────────────────────────
INSERT INTO zavod_anbar.herekat
    (material_kod, novu, miqdar, vahid_qiymet, menbe, sened_id, vaxt, qeyd)
SELECT 'BUGDA', 'INVENTAR_DUZELIS', 50, NULL, 'ELLE', s.id,
       now()-INTERVAL '35 days',
       'Inventar sayimi duzeldisi'
FROM zavod_sened.sened s WHERE s.edge_id = 112
LIMIT 1
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_m INT; v_h INT;
BEGIN
    SELECT count(*) INTO v_m FROM zavod_anbar.material;
    SELECT count(*) INTO v_h FROM zavod_anbar.herekat;
    RAISE NOTICE '22_seed_anbar: % material | % herekat', v_m, v_h;
    RAISE NOTICE 'PREMIKS qaliq yoxla:';
END $$;

SELECT
    kod, ad, qaliq,
    CASE WHEN qaliq < 0 THEN '*** KRITIK: mənfi qaliq ***' ELSE 'norma' END AS veziyyet
FROM zavod_anbar.qaliq
WHERE kod IN ('PREMIKS','QARGIDALI')
ORDER BY qaliq;
