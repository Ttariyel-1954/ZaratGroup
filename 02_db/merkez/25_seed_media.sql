-- Seed: zavod_media
-- 15 media: 10 foto, 3 video, 2 ses; 3-unde AI analiz

INSERT INTO zavod_media.media
    (novu, alt_novu, bashliq, obyekt_acari, mime_tipi, olcu_bayt,
     muddet_san, sha256, sha256_yoxlandi, cekilis_vaxti, yer, cihaz_ad,
     elaqeli_sened_id, ai_analiz, qebul_vaxti)
VALUES
    -- FOTO: Avadanlig muayinesi
    ('FOTO','AVADANLIQ_MUAYINE',
     'Qarisdiricinin disli cildi yoxlanisi',
     'SIYEZEN/2026/06/15/a1b2c3d4e5f6a1b2.jpg',
     'image/jpeg', 2847392, NULL,
     'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4',
     true,
     now()-INTERVAL '30 days', 'Istehsal sahesi', 'Hikvision DS-2CD2347G2',
     NULL,
     '{"tapinti": "disli cildde asima askarlanib", "temiz": false, "kritik": true}',
     now()-INTERVAL '30 days'),

    ('FOTO','XAMMAL_QEBUL',
     'Qargidali partiyasi fotofixasiyasi',
     'SIYEZEN/2026/06/15/b2c3d4e5f6a1b2c3.jpg',
     'image/jpeg', 3124680, NULL,
     'b2c3d4e5f6a1b2c3b2c3d4e5f6a1b2c3b2c3d4e5f6a1b2c3b2c3d4e5f6a1b2c3',
     true,
     now()-INTERVAL '30 days', 'Anbar giris', 'iPhone 15 Pro',
     NULL, NULL,
     now()-INTERVAL '30 days'),

    ('FOTO','AVADANLIQ_MUAYINE',
     'Elevator qayis ve makara yoxlanisi',
     'SIYEZEN/2026/06/18/c3d4e5f6a1b2c3d4.jpg',
     'image/jpeg', 1956240, NULL,
     'c3d4e5f6a1b2c3d4c3d4e5f6a1b2c3d4c3d4e5f6a1b2c3d4c3d4e5f6a1b2c3d4',
     true,
     now()-INTERVAL '27 days', 'Anbar', 'Hikvision DS-2CD2347G2',
     NULL,
     '{"tapinti": "qayis gevseyib, deysisdirme lazimdir", "temiz": false, "kritik": false}',
     now()-INTERVAL '27 days'),

    ('FOTO','TEHLUKESIZLIK',
     'Yangin sensoru aylik yoxlama',
     'SIYEZEN/2026/06/20/d4e5f6a1b2c3d4e5.jpg',
     'image/jpeg', 1234560, NULL,
     'd4e5f6a1b2c3d4e5d4e5f6a1b2c3d4e5d4e5f6a1b2c3d4e5d4e5f6a1b2c3d4e5',
     true,
     now()-INTERVAL '25 days', 'Anbar', 'iPhone 15 Pro',
     NULL, NULL,
     now()-INTERVAL '25 days'),

    ('FOTO','NOVBE_HESABAT',
     'Silo 1 seviyye gostericisi saat 06:00',
     'SIYEZEN/2026/07/01/e5f6a1b2c3d4e5f6.jpg',
     'image/jpeg', 987650, NULL,
     'e5f6a1b2c3d4e5f6e5f6a1b2c3d4e5f6e5f6a1b2c3d4e5f6e5f6a1b2c3d4e5f6',
     true,
     now()-INTERVAL '14 days', 'Silo 1', 'Daimi kamera',
     NULL, NULL,
     now()-INTERVAL '14 days'),

    ('FOTO','XAMMAL_QEBUL',
     'Soya unu canta numunesinin fotofixasiyasi',
     'SIYEZEN/2026/07/02/f6a1b2c3d4e5f6a1.jpg',
     'image/jpeg', 2341890, NULL,
     'f6a1b2c3d4e5f6a1f6a1b2c3d4e5f6a1f6a1b2c3d4e5f6a1f6a1b2c3d4e5f6a1',
     false,
     now()-INTERVAL '13 days', 'Anbar giris', 'iPhone 15 Pro',
     NULL, NULL,
     now()-INTERVAL '13 days'),

    ('FOTO','AVADANLIQ_MUAYINE',
     'Pnevmatik boru sistemi qovqalarin yoxlanisi',
     'SIYEZEN/2026/07/05/a2b3c4d5e6f1a2b3.jpg',
     'image/jpeg', 1678900, NULL,
     'a2b3c4d5e6f1a2b3a2b3c4d5e6f1a2b3a2b3c4d5e6f1a2b3a2b3c4d5e6f1a2b3',
     true,
     now()-INTERVAL '10 days', 'Istehsal sahesi', 'Hikvision DS-2CD2347G2',
     NULL, NULL,
     now()-INTERVAL '10 days'),

    ('FOTO','NOVBE_HESABAT',
     'Istehsal sehesi umumi gorunus saat 22:00',
     'SIYEZEN/2026/07/08/b3c4d5e6f1a2b3c4.jpg',
     'image/jpeg', 3456780, NULL,
     'b3c4d5e6f1a2b3c4b3c4d5e6f1a2b3c4b3c4d5e6f1a2b3c4b3c4d5e6f1a2b3c4',
     true,
     now()-INTERVAL '7 days', 'Istehsal sahesi', 'Daimi kamera',
     NULL, NULL,
     now()-INTERVAL '7 days'),

    ('FOTO','TEHLUKESIZLIK',
     'FHN yangin sogdurucu muveddeti yoxlama',
     'SIYEZEN/2026/07/10/c4d5e6f1a2b3c4d5.jpg',
     'image/jpeg', 1123450, NULL,
     'c4d5e6f1a2b3c4d5c4d5e6f1a2b3c4d5c4d5e6f1a2b3c4d5c4d5e6f1a2b3c4d5',
     false,
     now()-INTERVAL '5 days', 'Anbar', 'iPhone 15 Pro',
     NULL, NULL,
     now()-INTERVAL '5 days'),

    ('FOTO','DRON',
     'Zavod erazisinin hava fotou -- ay sonu monitoring',
     'SIYEZEN/2026/07/14/d5e6f1a2b3c4d5e6.jpg',
     'image/jpeg', 8920340, NULL,
     'd5e6f1a2b3c4d5e6d5e6f1a2b3c4d5e6d5e6f1a2b3c4d5e6d5e6f1a2b3c4d5e6',
     true,
     now()-INTERVAL '1 day', 'Zavod erazi', 'DJI Mini 4 Pro',
     NULL, NULL,
     now()-INTERVAL '1 day'),

    -- VIDEO: 3 eded
    ('VIDEO','AVADANLIQ_MUAYINE',
     'Mikser ucun doldurma prosesi video qeydi',
     'SIYEZEN/2026/06/22/v1a2b3c4d5e6f1a2.mp4',
     'video/mp4', 1248000000, 124,
     'v1a2b3c4d5e6f1a2v1a2b3c4d5e6f1a2v1a2b3c4d5e6f1a2v1a2b3c4d5e6f1a2',
     false,
     now()-INTERVAL '23 days', 'Istehsal sahesi', 'Hikvision DS-2CD2347G2',
     NULL, NULL,
     now()-INTERVAL '23 days'),

    ('VIDEO','TEHLUKESIZLIK',
     'Teshkilatda yangin meshtqleri - iyul 2026',
     'SIYEZEN/2026/07/03/v2b3c4d5e6f1a2b3.mp4',
     'video/mp4', 2147483647, 312,
     'v2b3c4d5e6f1a2b3v2b3c4d5e6f1a2b3v2b3c4d5e6f1a2b3v2b3c4d5e6f1a2b3',
     true,
     now()-INTERVAL '12 days', 'Zavod erazi', 'DJI Mini 4 Pro',
     NULL, NULL,
     now()-INTERVAL '12 days'),

    ('VIDEO','DRON',
     'Silo 1 ve 2 cercevenin hava videou',
     'SIYEZEN/2026/07/14/v3c4d5e6f1a2b3c4.mp4',
     'video/mp4', 3870000000, 540,
     'v3c4d5e6f1a2b3c4v3c4d5e6f1a2b3c4v3c4d5e6f1a2b3c4v3c4d5e6f1a2b3c4',
     false,
     now()-INTERVAL '1 day', 'Silo erazi', 'DJI Mini 4 Pro',
     NULL, NULL,
     now()-INTERVAL '1 day'),

    -- SES: 2 eded (novbe hesabati)
    ('SES','NOVBE_HESABAT',
     'Saat 06:00 novbe atesleme audio protokolu',
     'SIYEZEN/2026/07/07/s1d5e6f1a2b3c4d5.mp3',
     'audio/mpeg', 18450000, 1157,
     's1d5e6f1a2b3c4d5s1d5e6f1a2b3c4d5s1d5e6f1a2b3c4d5s1d5e6f1a2b3c4d5',
     false,
     now()-INTERVAL '8 days', 'Istehsal sahesi', 'Ses qeydi cihazi R-09HR',
     NULL, NULL,
     now()-INTERVAL '8 days'),

    ('SES','NOVBE_HESABAT',
     'Saat 14:00 novbe qebul-teslim audio protokolu',
     'SIYEZEN/2026/07/14/s2e6f1a2b3c4d5e6.mp3',
     'audio/mpeg', 21300000, 1331,
     's2e6f1a2b3c4d5e6s2e6f1a2b3c4d5e6s2e6f1a2b3c4d5e6s2e6f1a2b3c4d5e6',
     false,
     now()-INTERVAL '1 day', 'Istehsal sahesi', 'Ses qeydi cihazi R-09HR',
     NULL, NULL,
     now()-INTERVAL '1 day')

ON CONFLICT DO NOTHING;

DO $$
DECLARE v_f INT; v_v INT; v_s INT;
BEGIN
    SELECT count(*) INTO v_f FROM zavod_media.media WHERE novu='FOTO';
    SELECT count(*) INTO v_v FROM zavod_media.media WHERE novu='VIDEO';
    SELECT count(*) INTO v_s FROM zavod_media.media WHERE novu='SES';
    RAISE NOTICE '25_seed_media: % foto | % video | % ses', v_f, v_v, v_s;
END $$;
