-- Seed: zavod_sened
-- 15 sened, 15 fayl, 5 tesdiq, versiya (trigger vasitesile)
-- edge_id 100-114 (movcud max=1)

-- ── Senedler ──────────────────────────────────────────────────────────────────
INSERT INTO zavod_sened.sened
    (zavod_kod, edge_id, novu, nomre, sened_tarixi, qarsi_teref,
     qarsi_teref_voen, mebleg, status, daxil_eden, qebul_vaxti, metadata)
VALUES
    ('SIYEZEN',100,'QAIME_MEDAXIL','QM-2026-0041','2026-06-15','Aqro-Servis MMC',
     '1700012345',125000,'tesdiqlendi','operator1', now()-INTERVAL '30 days','{}'),
    ('SIYEZEN',101,'QAIME_MEDAXIL','QM-2026-0042','2026-06-18','Xezri Ticarət ASC',
     '1700019876',89500,'tesdiqlendi','operator1', now()-INTERVAL '27 days','{}'),
    ('SIYEZEN',102,'QAIME_MEXARIC','QX-2026-0031','2026-06-20','Baku Aqrar MMC',
     '1700054321',43200,'tesdiqlendi','operator2', now()-INTERVAL '25 days','{}'),
    ('SIYEZEN',103,'AKT_QEBUL',   'AQ-2026-0018','2026-06-22','Araz Taxil MMC',
     '1700067890',217800,'tesdiqlendi','operator1', now()-INTERVAL '23 days','{}'),
    ('SIYEZEN',104,'QAIME_MEDAXIL','QM-2026-0043','2026-06-25','Aqro-Servis MMC',
     '1700012345',98000,'tesdiqlendi','operator2', now()-INTERVAL '20 days','{}'),
    ('SIYEZEN',105,'TTN',          'TTN-2026-091','2026-06-28','Lojistik Plus',
     NULL,        35600,'tesdiqlendi','operator1', now()-INTERVAL '17 days','{}'),
    ('SIYEZEN',106,'AKT_TEHVIL',  'AT-2026-0009','2026-06-30','Baku Aqrar MMC',
     '1700054321',78400,'tesdiqlendi','operator2', now()-INTERVAL '15 days','{}'),
    ('SIYEZEN',107,'QAIME_MEDAXIL','QM-2026-0044','2026-07-02','Soya-Tur MMC',
     '1700023456',156300,'tesdiqlendi','operator1', now()-INTERVAL '13 days','{}'),
    ('SIYEZEN',108,'QAIME_MEXARIC','QX-2026-0032','2026-07-04','Xazər-Yem',
     '1700034567',62100,'tesdiqlendi','operator2', now()-INTERVAL '11 days','{}'),
    ('SIYEZEN',109,'AKT_QEBUL',   'AQ-2026-0019','2026-07-06','Araz Taxil MMC',
     '1700067890',195400,'tesdiqlendi','operator1', now()-INTERVAL '9 days','{}'),
    ('SIYEZEN',110,'QAIME_MEDAXIL','QM-2026-0045','2026-07-08','Baliq-Un Az',
     '1700078901',44800,'tesdiq_gozleyir','operator2',now()-INTERVAL '7 days','{}'),
    ('SIYEZEN',111,'TTN',          'TTN-2026-092','2026-07-09','Lojistik Plus',
     NULL,        28500,'tesdiq_gozleyir','operator1',now()-INTERVAL '6 days','{}'),
    ('SIYEZEN',112,'AKT_SILINME', 'AS-2026-0003','2026-07-10','Anbar Komissiyasi',
     NULL,         9200,'tesdiq_gozleyir','operator2',now()-INTERVAL '5 days','{}'),
    ('SIYEZEN',113,'QAIME_MEDAXIL','QM-2026-0046','2026-07-12','Aqro-Servis MMC',
     '1700012345',134600,'qaralama',   'operator1', now()-INTERVAL '3 days','{}'),
    ('SIYEZEN',114,'QAIME_MEXARIC','QX-2026-0033','2026-07-14','Xezri Ticarət ASC',
     '1700019876',51700,'qaralama',   'operator2', now()-INTERVAL '1 days','{}')
ON CONFLICT (zavod_kod, edge_id) DO NOTHING;

-- ── Fayllar (her senede 1 PDF) ────────────────────────────────────────────────
INSERT INTO zavod_sened.fayl
    (zavod_kod, edge_id, sened_id, orijinal_ad, mime_tipi, olcu_bayt,
     obyekt_acari, sha256, sha256_yoxlandi, qebul_vaxti)
SELECT
    'SIYEZEN',
    s.edge_id,
    s.id,
    'sened_' || s.nomre || '.pdf',
    'application/pdf',
    (500000 + (RANDOM() * 2000000)::bigint),
    'SIYEZEN/' || TO_CHAR(s.sened_tarixi,'YYYY/MM/DD') || '/' ||
        MD5(s.nomre) || '.pdf',
    MD5(s.nomre || 'a') || MD5(s.nomre || 'b'),
    (RANDOM() > 0.3),
    s.qebul_vaxti
FROM zavod_sened.sened s
WHERE s.edge_id BETWEEN 100 AND 114
ON CONFLICT (zavod_kod, edge_id) DO NOTHING;

-- ── Tesdiqler ─────────────────────────────────────────────────────────────────
INSERT INTO zavod_sened.tesdiq
    (sened_id, merhele, rol, tesdiq_eden, qerar, yorum, qerar_vaxti)
SELECT s.id, 1, 'muhasib', 'Leyla Mammadova', 'tesdiq',
       'Hesablar uygundir', s.qebul_vaxti + INTERVAL '2 hours'
FROM zavod_sened.sened s
WHERE s.edge_id IN (100,101,103,104,107)
  AND s.status = 'tesdiqlendi'
ON CONFLICT (sened_id, merhele) DO NOTHING;

INSERT INTO zavod_sened.tesdiq
    (sened_id, merhele, rol, tesdiq_eden, qerar, yorum, qerar_vaxti)
SELECT s.id, 2, 'direktor', 'Anar Huseynov', 'tesdiq',
       NULL, s.qebul_vaxti + INTERVAL '5 hours'
FROM zavod_sened.sened s
WHERE s.edge_id IN (103,107)
  AND s.status = 'tesdiqlendi'
ON CONFLICT (sened_id, merhele) DO NOTHING;

-- ── Versiya tarixcesi: 3 senedi guncelleme (trigger versiyani yazacaq) ────────
UPDATE zavod_sened.sened
SET    status = 'tesdiq_gozleyir'
WHERE  edge_id = 100 AND zavod_kod = 'SIYEZEN'
  AND  status = 'tesdiqlendi';   -- yalniz movcudsa

UPDATE zavod_sened.sened
SET    status = 'tesdiqlendi'
WHERE  edge_id = 100 AND zavod_kod = 'SIYEZEN'
  AND  status = 'tesdiq_gozleyir';

UPDATE zavod_sened.sened
SET    metadata = metadata || '{"duzeltme":"maliyye deyisikliyi"}'
WHERE  edge_id = 104 AND zavod_kod = 'SIYEZEN';

DO $$
DECLARE v_s INT; v_f INT; v_t INT; v_v INT;
BEGIN
    SELECT count(*) INTO v_s FROM zavod_sened.sened;
    SELECT count(*) INTO v_f FROM zavod_sened.fayl;
    SELECT count(*) INTO v_t FROM zavod_sened.tesdiq;
    SELECT count(*) INTO v_v FROM zavod_sened.versiya;
    RAISE NOTICE '21_seed_sened: % sened | % fayl | % tesdiq | % versiya',
        v_s, v_f, v_t, v_v;
END $$;
