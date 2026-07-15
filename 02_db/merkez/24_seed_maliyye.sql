-- Seed: zavod_maliyye
-- 15 faktura, 12 odenis, 20 bank_herekat, 10 emek_haqqi

-- ── Fakturalar ────────────────────────────────────────────────────────────────
INSERT INTO zavod_maliyye.faktura
    (novu, nomre, tarix, qarsi_teref, qarsi_teref_voen,
     mebleg_edvsiz, edv, mebleg_cemi, status, qeyd)
VALUES
    ('ALIS','F-ALS-2026-0041','2026-06-15','Aqro-Servis MMC','1700012345',
     104167, 20833, 125000,'odenilib','Qargidali tedariki QM-0041'),
    ('ALIS','F-ALS-2026-0042','2026-06-18','Xezri Ticarət ASC','1700019876',
     74583, 14917, 89500,'odenilib','Bugda tedariki QM-0042'),
    ('SATIS','F-SAT-2026-0021','2026-06-20','Baku Aqrar MMC','1700054321',
     36000, 7200, 43200,'odenilib','Broyler yemi satisi QX-0031'),
    ('ALIS','F-ALS-2026-0043','2026-06-22','Araz Taxil MMC','1700067890',
     181500, 36300, 217800,'odenilib','Bugda ve soya tedariki AQ-0018'),
    ('ALIS','F-ALS-2026-0044','2026-06-25','Aqro-Servis MMC','1700012345',
     81667, 16333, 98000,'qismen','Premiks tedariki QM-0043'),
    ('SATIS','F-SAT-2026-0022','2026-06-28','Xazər-Yem','1700034567',
     29667, 5933, 35600,'odenilib','Davar yemi satisi TTN-091'),
    ('SATIS','F-SAT-2026-0023','2026-06-30','Baku Aqrar MMC','1700054321',
     65333, 13067, 78400,'qismen','Broyler final yemi AT-0009'),
    ('ALIS','F-ALS-2026-0045','2026-07-02','Soya-Tur MMC','1700023456',
     130250, 26050, 156300,'qismen','Soya unu tedariki QM-0044'),
    ('SATIS','F-SAT-2026-0024','2026-07-04','Xazər-Yem','1700034567',
     51750, 10350, 62100,'odenilmeyib','Toyuq yemi QX-0032'),
    ('SATIS','F-SAT-2026-0025','2026-07-06','Azfeed JSC','1700089012',
     162833, 32567, 195400,'odenilmeyib','Broyler start yemi AQ-0019'),
    ('ALIS','F-ALS-2026-0046','2026-07-08','Baliq-Un Az','1700078901',
     37333, 7467, 44800,'odenilmeyib','Baliq unu QM-0045'),
    ('SATIS','F-SAT-2026-0026','2026-07-09','Kend Yemleri MMC','1700091234',
     23750, 4750, 28500,'odenilmeyib','Davar yemi satisi TTN-092'),
    ('ALIS','F-ALS-2026-0047','2026-07-10','Vitagen Az','1700056789',
     18500, 3700, 22200,'odenilmeyib','Vitamin premiks AS-0003'),
    ('SATIS','F-SAT-2026-0027','2026-07-12','Baku Aqrar MMC','1700054321',
     112167, 22433, 134600,'odenilmeyib','Broyler start yemi QM-0046'),
    ('ALIS','F-ALS-2026-0048','2026-07-14','Soya-Tur MMC','1700023456',
     43083, 8617, 51700,'odenilmeyib','Soya unu QX-0033')
ON CONFLICT DO NOTHING;

-- ── Odenisler ─────────────────────────────────────────────────────────────────
INSERT INTO zavod_maliyye.odenis
    (faktura_id, novu, mebleg, tarix, bank, hesab_nomre, tesvir)
SELECT f.id, 'KOCURME', f.mebleg_cemi,
       f.tarix + INTERVAL '5 days',
       'Kapital Bank', 'AZ21AIIB38081934556219',
       f.nomre || ' odenis'
FROM zavod_maliyye.faktura f
WHERE f.status = 'odenilib'
  AND f.nomre IN ('F-ALS-2026-0041','F-ALS-2026-0042','F-SAT-2026-0021',
                  'F-ALS-2026-0043','F-SAT-2026-0022')
ON CONFLICT DO NOTHING;

-- Qismi odenisler
INSERT INTO zavod_maliyye.odenis
    (faktura_id, novu, mebleg, tarix, bank, hesab_nomre, tesvir)
SELECT f.id, 'KOCURME', ROUND(f.mebleg_cemi * 0.6),
       f.tarix + INTERVAL '7 days',
       'ABB Bank', 'AZ94NABZ01350100000000105944',
       f.nomre || ' - 60% avans odenis'
FROM zavod_maliyye.faktura f
WHERE f.status = 'qismen'
  AND f.nomre IN ('F-ALS-2026-0044','F-SAT-2026-0023','F-ALS-2026-0045')
ON CONFLICT DO NOTHING;

-- Tam odeyen amma F-SAT-0024 gecikir
INSERT INTO zavod_maliyye.odenis
    (faktura_id, novu, mebleg, tarix, bank, hesab_nomre, tesvir)
SELECT f.id, 'KOCURME', ROUND(f.mebleg_cemi * 0.9),
       CURRENT_DATE - INTERVAL '3 days',
       'Kapital Bank', 'AZ21AIIB38081934556219',
       'F-SAT-2026-0023 qismi odenis'
FROM zavod_maliyye.faktura f
WHERE f.nomre = 'F-SAT-2026-0023'
ON CONFLICT DO NOTHING;

-- ── Bank herekatlar ───────────────────────────────────────────────────────────
INSERT INTO zavod_maliyye.bank_herekat
    (tarix, bank, novu, mebleg, qarsi_teref, tesvir, faktura_id)
VALUES
    ('2026-06-20','Kapital Bank','MEDAXIL',43200,'Baku Aqrar MMC',
     'F-SAT-2026-0021 odenis daxilolub', NULL),
    ('2026-06-23','Kapital Bank','MEXARIC',125000,'Aqro-Servis MMC',
     'F-ALS-2026-0041 odenis', NULL),
    ('2026-06-24','ABB Bank','MEXARIC',89500,'Xezri Ticarət ASC',
     'F-ALS-2026-0042 odenis', NULL),
    ('2026-06-25','Kapital Bank','MEDAXIL',35600,'Xazər-Yem',
     'F-SAT-2026-0022 odenis', NULL),
    ('2026-06-28','Kapital Bank','MEXARIC',217800,'Araz Taxil MMC',
     'F-ALS-2026-0043 odenis', NULL),
    ('2026-07-01','Kapital Bank','MEDAXIL',78400,'Baku Aqrar MMC',
     'F-SAT-2026-0023 qismi', NULL),
    ('2026-07-03','ABB Bank','MEXARIC',58800,'Aqro-Servis MMC',
     'F-ALS-2026-0044 avans (60%)', NULL),
    ('2026-07-05','ABB Bank','MEXARIC',93780,'Soya-Tur MMC',
     'F-ALS-2026-0045 avans (60%)', NULL),
    ('2026-07-07','Kapital Bank','MEXARIC',47120,'Baku Aqrar MMC',
     'F-SAT-2026-0023 qalan hisse', NULL),
    ('2026-07-10','Kapital Bank','MEDAXIL',5000,'Müxtəlif',
     'Kassa daxilolma', NULL),
    ('2026-07-10','ABB Bank','MEXARIC',3500,'Kommunal xidmetler',
     'Iyul kommunal odenis', NULL),
    ('2026-07-11','Kapital Bank','MEXARIC',28500,'Fərdi sahibkar Aliyev',
     'Nəqliyyat xidmeti', NULL),
    ('2026-07-12','Kapital Bank','MEXARIC',18700,'Azenerji',
     'Elektrik enerjisi iyul', NULL),
    ('2026-07-12','ABB Bank','MEXARIC',12400,'Azerbaycan Su Kanali',
     'Su ve kanalizasiya iyul', NULL),
    ('2026-07-13','Kapital Bank','MEXARIC',8600,'Azərsu ASC',
     'Texniki su iyul', NULL),
    ('2026-07-13','ABB Bank','MEXARIC',44800,'Baliq-Un Az',
     'F-ALS-2026-0046 avans', NULL),
    ('2026-07-14','Kapital Bank','MEDAXIL',15000,'Xazər-Yem',
     'Avans odenis daxilolma', NULL),
    ('2026-07-14','Kapital Bank','MEXARIC',22200,'Vitagen Az',
     'F-ALS-2026-0047 odenis', NULL),
    ('2026-07-15','ABB Bank','MEXARIC',43083,'Soya-Tur MMC',
     'F-ALS-2026-0048 avans', NULL),
    ('2026-07-15','Kapital Bank','MEDAXIL',9800,'Müxtəlif',
     'Kassa daxilolma', NULL)
ON CONFLICT DO NOTHING;

-- ── Emek haqqi (2 dövr: iyun + iyul 2026) ────────────────────────────────────
INSERT INTO zavod_maliyye.emek_haqqi
    (dovr, vezife, ishci_kod, ish_saati, mebleg_brutto, mebleg_netto)
VALUES
    -- Iyun 2026
    ('2026-06-01','Mudir musavir',     'EMP-001', 176, 2800, 2380),
    ('2026-06-01','Baş texnoloq',      'EMP-002', 176, 2200, 1870),
    ('2026-06-01','Anbar muduru',      'EMP-003', 176, 1800, 1530),
    ('2026-06-01','Operator',          'EMP-004', 176, 1400, 1190),
    ('2026-06-01','Yuk masincilar',    'EMP-005', 176, 1200, 1020),
    -- Iyul 2026
    ('2026-07-01','Mudir musavir',     'EMP-001', 184, 2800, 2380),
    ('2026-07-01','Baş texnoloq',      'EMP-002', 184, 2200, 1870),
    ('2026-07-01','Anbar muduru',      'EMP-003', 160, 1636, 1390),
    ('2026-07-01','Operator',          'EMP-004', 184, 1400, 1190),
    ('2026-07-01','Yuk masincilar',    'EMP-005', 184, 1200, 1020)
ON CONFLICT (dovr, ishci_kod) DO NOTHING;

DO $$
DECLARE v_f INT; v_o INT; v_b INT; v_e INT;
BEGIN
    SELECT count(*) INTO v_f FROM zavod_maliyye.faktura;
    SELECT count(*) INTO v_o FROM zavod_maliyye.odenis;
    SELECT count(*) INTO v_b FROM zavod_maliyye.bank_herekat;
    SELECT count(*) INTO v_e FROM zavod_maliyye.emek_haqqi;
    RAISE NOTICE '24_seed_maliyye: % faktura | % odenis | % bank_herekat | % emek_haqqi',
        v_f, v_o, v_b, v_e;
END $$;
