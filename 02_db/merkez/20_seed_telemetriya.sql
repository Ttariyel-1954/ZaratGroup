-- Seed: zavod_telemetriya
-- 7 sensor, son 48 saatda 20 olcme, 4 xeberdarliq

-- ── Cihazlar ─────────────────────────────────────────────────────────────────
INSERT INTO zavod_telemetriya.cihaz
    (kod, ad, tip, vahid, yer, min_norma, max_norma, aktiv, qurulma_tarixi)
VALUES
    ('S001','Temperatur -- Silo 1',    'TEMPERATUR','C',   'Silo 1',          15,  38,  true, '2024-03-15'),
    ('S002','Rutubet -- Silo 1',       'RUTUBET',   '%',   'Silo 1',          10,  70,  true, '2024-03-15'),
    ('S003','Ceki -- Anbar Giris',     'CEKI',      'kq',  'Anbar',            0,  50000, true,'2024-05-01'),
    ('S004','Enerji -- Istehsal',      'ENERJI',    'kW',  'Istehsal sahesi',  0,  500, true, '2024-05-01'),
    ('S005','Suret -- Qarisdiricisi',  'SURET',     'rpm', 'Istehsal sahesi',  0,  3000, true,'2024-05-01'),
    ('S006','Qaz -- Kazanxana',        'QAZ',       'ppm', 'Kazanxana',        0,  50,  true, '2024-09-10'),
    ('S007','Seviyye -- Silo 2',       'SEVIYYE',   '%',   'Silo 2',           5,  95,  true, '2024-09-10')
ON CONFLICT (kod) DO NOTHING;

-- ── FK: olcme.cihaz_kod → cihaz.kod (cihaz datasi elave edilenden sonra) ─────
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'olcme_cihaz_fk' AND conrelid = 'zavod_telemetriya.olcme'::regclass
    ) THEN
        ALTER TABLE zavod_telemetriya.olcme
            ADD CONSTRAINT olcme_cihaz_fk
            FOREIGN KEY (cihaz_kod) REFERENCES zavod_telemetriya.cihaz(kod);
        RAISE NOTICE 'FK olcme_cihaz_fk elave edildi';
    ELSE
        RAISE NOTICE 'FK olcme_cihaz_fk artiq movcuddur';
    END IF;
END $$;

-- ── Olcmeler: son 48 saatda her sensor ucun 20 olcme ─────────────────────────
-- Normal araligda teskhufi qiymetler + 2-3 anomaliya (keyfiyyet=0)
INSERT INTO zavod_telemetriya.olcme
    (zavod, edge_id, cihaz_kod, olcme_vaxti, qiymet, keyfiyyet)
SELECT
    'siyezen',
    100000 + ((ROW_NUMBER() OVER (ORDER BY ts, ck))::bigint),
    ck,
    ts,
    ROUND(CASE ck
        WHEN 'S001' THEN (22 + RANDOM() * 8)::numeric
        WHEN 'S002' THEN (35 + RANDOM() * 25)::numeric
        WHEN 'S003' THEN (18000 + RANDOM() * 12000)::numeric
        WHEN 'S004' THEN (180 + RANDOM() * 120)::numeric
        WHEN 'S005' THEN (1200 + RANDOM() * 800)::numeric
        WHEN 'S006' THEN (5 + RANDOM() * 30)::numeric
        WHEN 'S007' THEN (45 + RANDOM() * 40)::numeric
    END, 2) AS qiymet,
    1 AS keyfiyyet
FROM (
    SELECT
        c.kod AS ck,
        now() - (n * INTERVAL '2.4 hours') AS ts
    FROM zavod_telemetriya.cihaz c
    CROSS JOIN generate_series(0, 19) AS n
) sub
ON CONFLICT DO NOTHING;

-- ── Anomaliyalar: 3 qiymet normaldan kenarda ──────────────────────────────────
INSERT INTO zavod_telemetriya.olcme
    (zavod, edge_id, cihaz_kod, olcme_vaxti, qiymet, keyfiyyet)
VALUES
    ('siyezen', 100200, 'S001', now() - INTERVAL '6 hours',  42.5,   0),
    ('siyezen', 100201, 'S006', now() - INTERVAL '14 hours', 67.3,   0),
    ('siyezen', 100202, 'S002', now() - INTERVAL '31 hours', 78.2,   0)
ON CONFLICT DO NOTHING;

-- ── Xeberdarliqlar ────────────────────────────────────────────────────────────
INSERT INTO zavod_telemetriya.xeberdarliq
    (cihaz_kod, novu, seviyye, qiymet, mesaj, yaranma_vaxti, hell_olunub, hell_vaxti)
VALUES
    ('S001','HEDD_ASILDI','kritik',     42.5,
     'Temperatur maksimum heddi asdi: 42.5 C (max: 38 C)',
     now() - INTERVAL '6 hours',  false, NULL),
    ('S006','HEDD_ASILDI','xeberdarliq',67.3,
     'Qaz sensoru xeberdarliq heddi asdi: 67.3 ppm (max: 50 ppm)',
     now() - INTERVAL '14 hours', true,  now() - INTERVAL '12 hours'),
    ('S002','HEDD_ASILDI','xeberdarliq',78.2,
     'Rutubet maksimum heddi asdi: 78.2% (max: 70%)',
     now() - INTERVAL '31 hours', true,  now() - INTERVAL '28 hours'),
    ('S007','ANOMAL',     'info',       NULL,
     'Seviyye sensoru qisa muddet rabitesi itirdi',
     now() - INTERVAL '52 hours', true,  now() - INTERVAL '50 hours')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_cihaz INT; v_olcme INT; v_xeb INT;
BEGIN
    SELECT count(*) INTO v_cihaz  FROM zavod_telemetriya.cihaz;
    SELECT count(*) INTO v_olcme  FROM zavod_telemetriya.olcme;
    SELECT count(*) INTO v_xeb    FROM zavod_telemetriya.xeberdarliq;
    RAISE NOTICE '20_seed_telemetriya: % cihaz | % olcme | % xeberdarliq',
        v_cihaz, v_olcme, v_xeb;
END $$;
