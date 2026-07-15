-- Seed: zavod_ai
-- 8 cixaris, 5 yeni qerar (kritik hibrid + xeberdarliq + info), 35 jurnal

-- ── Cixarisler (sened oxuma naticeleri) ──────────────────────────────────────
INSERT INTO zavod_ai.cixaris
    (sened_id, fayl_id, agent_kod, model, netice, eminlik, status,
     insan_duzelisi, baxan, baxis_vaxti, yaradilma)
SELECT
    s.id,
    f.id,
    'agent-sened-v2',
    'claude-sonnet-4-6',
    jsonb_build_object(
        'novu',         s.novu,
        'nomre',        s.nomre,
        'tarix',        s.sened_tarixi::text,
        'qarsi_teref',  s.qarsi_teref,
        'mebleg',       s.mebleg,
        'materiallar',  '[]'::jsonb
    ),
    jsonb_build_object('umumi', 0.92, 'nomre', 0.98, 'mebleg', 0.87),
    CASE s.edge_id
        WHEN 100 THEN 'tesdiqlendi'
        WHEN 101 THEN 'tesdiqlendi'
        WHEN 102 THEN 'duzelis_edildi'
        WHEN 103 THEN 'tesdiqlendi'
        WHEN 104 THEN 'tesdiqlendi'
        WHEN 107 THEN 'tesdiqlendi'
        WHEN 108 THEN 'baxilir'
        WHEN 109 THEN 'teklif'
    END,
    CASE WHEN s.edge_id = 102
        THEN '{"mebleg": 43200, "not": "AI 42800 oxudu, duzeldildi"}'::jsonb
        ELSE NULL
    END,
    CASE WHEN s.edge_id IN (100,101,102,103,104,107)
        THEN 'Leyla Mammadova'
        ELSE NULL
    END,
    CASE WHEN s.edge_id IN (100,101,102,103,104,107)
        THEN s.qebul_vaxti + INTERVAL '1 hour'
        ELSE NULL
    END,
    s.qebul_vaxti + INTERVAL '5 minutes'
FROM zavod_sened.sened s
JOIN zavod_sened.fayl f ON f.sened_id = s.id
WHERE s.edge_id IN (100,101,102,103,104,107,108,109)
  AND s.zavod_kod = 'SIYEZEN'
ON CONFLICT DO NOTHING;

-- ── Yeni qerarlar ─────────────────────────────────────────────────────────────
-- 1. KRİTİK hibrid: qaimede 5000 kq, sensor 4700 kq goturur
INSERT INTO zavod_ai.qerar
    (agent_kod, sened_id, material_kod, seviyye, basliq, izah,
     delil, tovsiyye, status, yaradilma)
SELECT
    'agent-hibrid-v1',
    s.id,
    'QARGIDALI',
    'kritik',
    'Qaimede 5000 kq, sensor 4700 kq -- 300 kq ferq',
    'QM-2026-0041 senedinде 5000 kq qargidali medaxili qeyde alinib. '
    'S003 (Ceki sensoru) ise 4700 kq fix edib. '
    '300 kq (6%) ferq normaldan coxdur. '
    'Yoxlama aparilmalidir.',
    jsonb_build_object(
        'qaime_miqdar',   5000,
        'sensor_miqdar',  4700,
        'ferq_kq',        300,
        'ferq_faiz',      6.0,
        'sensor_kod',     'S003',
        'sened_nomre',    'QM-2026-0041'
    ),
    '["Fiziki canlaghma aparin","Terezini kalibrleyin","Novbeti teslimde nazirim nezareti"]'::jsonb,
    'yeni',
    now() - INTERVAL '30 days'
FROM zavod_sened.sened s
WHERE s.edge_id = 100 AND s.zavod_kod = 'SIYEZEN'
LIMIT 1
ON CONFLICT DO NOTHING;

-- 2. KRİTİK: PREMIKS qaligi menfidi (seed_anbar-dan ireli gelir)
INSERT INTO zavod_ai.qerar
    (agent_kod, material_kod, seviyye, basliq, izah,
     delil, tovsiyye, status, yaradilma)
VALUES
    ('agent-anbar-v2',
     'PREMIKS',
     'kritik',
     'PREMIKS anbar qaligi menfidi: -150 kq',
     'Vitamin-mineral premiks qaligi -150 kq-a dusub. '
     'Son mexaric (P-2026-041) sifaris verilmeden qaliq yoxlanilmamis. '
     'Istehsal dayanacaq thlukesi var.',
     '{"qaliq": -150, "min_qaliq": 50, "son_medaxil": "2026-05-16", "son_mexaric": "P-2026-041"}'::jsonb,
     '["Tezlikle premiks sifaris verin","P-2026-045 sifarisini dayandirin","Anbar muduru ile elaqe saxlayin"]'::jsonb,
     'yeni',
     now() - INTERVAL '10 days')
ON CONFLICT DO NOTHING;

-- 3. XƏBƏRDARLIQ: S001 temperatur hedd asdi
INSERT INTO zavod_ai.qerar
    (agent_kod, seviyye, basliq, izah,
     delil, tovsiyye, status, yaradilma)
VALUES
    ('agent-sensor-v1',
     'xeberdarliq',
     'Silo 1 temperaturu kritik hedd asdi: 42.5 C',
     'S001 sensoru son 6 saatda 42.5°C qeydetti. Normal aralig 15-38°C. '
     'Uzun mudde bu temperaturda mehsul keyfiyyeti zeifleye biler.',
     '{"sensor": "S001", "qiymet": 42.5, "max_norma": 38, "ferq": 4.5}'::jsonb,
     '["Silo havalandirmasini yoxlayin","Temperatur manbeini mueyyen edin","24 saat monitorinq aparın"]'::jsonb,
     'yeni',
     now() - INTERVAL '6 hours')
ON CONFLICT DO NOTHING;

-- 4. XƏBƏRDARLIQ: Bugda az qalıb
INSERT INTO zavod_ai.qerar
    (agent_kod, material_kod, seviyye, basliq, izah,
     delil, tovsiyye, status, yaradilma)
VALUES
    ('agent-anbar-v2',
     'BUGDA',
     'xeberdarliq',
     'Bugda qaligi minimum heddine yakinlasir',
     'Bugda mevcut qaligi hesablananda ~3500 kq gorunur. '
     'Min.qaliq 500 kq, amma P-2026-046 sifarisi 5000 kq teleb edir. '
     'Tezlikle tedarik lazimdir.',
     '{"qaliq": 3500, "min_qaliq": 500, "novbeti_sifaris": "P-2026-046", "lazim": 5000}'::jsonb,
     '["Araz Taxil MMC ile elaqe saxlayin","P-2026-046 baslama tarixini uzadin"]'::jsonb,
     'yeni',
     now() - INTERVAL '3 days')
ON CONFLICT DO NOTHING;

-- 5. İNFO: P-2026-041 sapma hesabati
INSERT INTO zavod_ai.qerar
    (agent_kod, sifaris_id, seviyye, basliq, izah,
     delil, tovsiyye, status, yaradilma)
SELECT
    'agent-istehsal-v1',
    s.id,
    'info',
    'P-2026-041 sapma hesabati: 2 material normadan kend',
    'Broyler Start partiyasi P-2026-041 tamamlandi. '
    'Qargidali 1.85% artiq, medde unu 6.67% artiq serf olundu. '
    'Soya unu ise 1.43% az serf edildi. '
    'Qeyde alinib, nezaret devam edir.',
    jsonb_build_object(
        'partiya',         'P-2026-041',
        'resept',          'YEM_BROYLER_START',
        'qargidali_sapma', '+1.85%',
        'medde_sapma',     '+6.67%',
        'soya_sapma',      '-1.43%'
    ),
    '["Doz. sistemi texnoloq terefinden yoxlansin","Bir daha normativ kitleler tesdiq edilsin"]'::jsonb,
    'yeni',
    now() - INTERVAL '34 days'
FROM zavod_istehsal.sifaris s
WHERE s.partiya_no = 'P-2026-041'
LIMIT 1
ON CONFLICT DO NOTHING;

-- ── Jurnal (son 7 gunde 35 cagiris) ──────────────────────────────────────────
WITH sened_ids AS (
    SELECT id, edge_id FROM zavod_sened.sened
    WHERE edge_id BETWEEN 100 AND 111 AND zavod_kod = 'SIYEZEN'
),
src AS (
    SELECT
        n,
        CASE (n % 3)
            WHEN 0 THEN 'agent-sened-v2'
            WHEN 1 THEN 'agent-anbar-v2'
            ELSE       'agent-hibrid-v1'
        END AS agent_kod,
        CASE WHEN n % 4 = 0
            THEN (SELECT id FROM sened_ids WHERE edge_id = 100 + (n % 12) LIMIT 1)
            ELSE NULL
        END AS sened_id,
        now() - (n * INTERVAL '4.8 hours') AS vaxt
    FROM generate_series(0, 34) AS n
)
INSERT INTO zavod_ai.jurnal
    (agent_kod, model, sened_id, giris_token, cixis_token,
     muddet_ms, ugurlu, xeta, vaxt)
SELECT
    src.agent_kod,
    'claude-sonnet-4-6',
    src.sened_id,
    (800  + (RANDOM() * 2400)::int),
    (150  + (RANDOM() * 600)::int),
    (1200 + (RANDOM() * 6800)::int),
    (RANDOM() > 0.06),
    CASE WHEN RANDOM() < 0.06 THEN 'LLM cavab vermedi, timeout (30s)' ELSE NULL END,
    src.vaxt
FROM src
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_c INT; v_q INT; v_j INT; v_krit INT;
BEGIN
    SELECT count(*) INTO v_c    FROM zavod_ai.cixaris;
    SELECT count(*) INTO v_q    FROM zavod_ai.qerar;
    SELECT count(*) INTO v_j    FROM zavod_ai.jurnal;
    SELECT count(*) INTO v_krit FROM zavod_ai.qerar WHERE seviyye = 'kritik';
    RAISE NOTICE '26_seed_ai: % cixaris | % qerar (% kritik) | % jurnal',
        v_c, v_q, v_krit, v_j;
END $$;
