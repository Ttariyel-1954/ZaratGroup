cd ~/Desktop/Zarat_Faza2_Zavod

cat > 02_db/edge/01_cedveller.sql << 'EOF'
-- ============================================================
-- Zarat Faza 2 — zavod_edge_db — cədvəllər
-- Fayl: 02_db/edge/01_cedveller.sql
-- ============================================================

-- ---- 1. SENSOR TİPLƏRİ (lüğət) ----
CREATE TABLE IF NOT EXISTS sensor_tipi (
    kod          VARCHAR(20)  PRIMARY KEY,
    ad           VARCHAR(80)  NOT NULL,
    vahid        VARCHAR(15)  NOT NULL,
    min_hedd     NUMERIC(10,3),
    max_hedd     NUMERIC(10,3),
    tesvir       TEXT,
    yaradilma    TIMESTAMPTZ  NOT NULL DEFAULT now()
);
COMMENT ON TABLE  sensor_tipi IS 'Sensor novlerinin lugeti ve normal heddleri';
COMMENT ON COLUMN sensor_tipi.min_hedd IS 'Bu hedden asagi = anomaliya (ders 6)';
COMMENT ON COLUMN sensor_tipi.max_hedd IS 'Bu hedden yuxari = anomaliya (ders 6)';

-- ---- 2. CİHAZLAR (fiziki sensorlar) ----
CREATE TABLE IF NOT EXISTS cihaz (
    kod              VARCHAR(20)  PRIMARY KEY,
    sensor_tipi_kod  VARCHAR(20)  NOT NULL REFERENCES sensor_tipi(kod),
    ad               VARCHAR(100) NOT NULL,
    yer              VARCHAR(100),
    status           VARCHAR(15)  NOT NULL DEFAULT 'aktiv'
                     CHECK (status IN ('aktiv','deaktiv','xarab')),
    qurasdirilma     DATE,
    yaradilma        TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cihaz_tipi ON cihaz(sensor_tipi_kod);
COMMENT ON TABLE cihaz IS 'Zavodda qurasdirilmis fiziki sensorlar';

-- ---- 3. ÖLÇMƏLƏR (əsas cədvəl — partisiyalı) ----
CREATE TABLE IF NOT EXISTS olcme (
    id           BIGINT       GENERATED ALWAYS AS IDENTITY,
    cihaz_kod    VARCHAR(20)  NOT NULL REFERENCES cihaz(kod),
    olcme_vaxti  TIMESTAMPTZ  NOT NULL,
    qiymet       NUMERIC(12,4) NOT NULL,
    keyfiyyet    SMALLINT     NOT NULL DEFAULT 1,
    sync_status  SMALLINT     NOT NULL DEFAULT 0,
    yaradilma    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (id, olcme_vaxti)
) PARTITION BY RANGE (olcme_vaxti);

CREATE INDEX IF NOT EXISTS idx_olcme_cihaz_vaxt
    ON olcme (cihaz_kod, olcme_vaxti DESC);
CREATE INDEX IF NOT EXISTS idx_olcme_sync
    ON olcme (sync_status, olcme_vaxti) WHERE sync_status = 0;

COMMENT ON TABLE  olcme IS 'Sensorlardan gelen xam olcmeler — ayliq partisiyali';
COMMENT ON COLUMN olcme.sync_status IS 'Outbox: 0=gonderilmeyib, 1=gonderilib';
COMMENT ON COLUMN olcme.keyfiyyet IS '1=etibarli, 0=validasiyadan kecmeyib (ders 5)';

-- ---- 4. XƏBƏRDARLIQLAR (anomaliya jurnalı) ----
CREATE TABLE IF NOT EXISTS xeberdarliq (
    id           BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cihaz_kod    VARCHAR(20)  NOT NULL REFERENCES cihaz(kod),
    olcme_vaxti  TIMESTAMPTZ  NOT NULL,
    qiymet       NUMERIC(12,4) NOT NULL,
    novu         VARCHAR(20)  NOT NULL
                 CHECK (novu IN ('yuxari_hedd','asagi_hedd','cihaz_susur')),
    mesaj        TEXT,
    hell_olundu  BOOLEAN      NOT NULL DEFAULT false,
    yaradilma    TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_xeber_cihaz ON xeberdarliq(cihaz_kod, yaradilma DESC);
CREATE INDEX IF NOT EXISTS idx_xeber_hell ON xeberdarliq(hell_olundu) WHERE hell_olundu = false;
COMMENT ON TABLE xeberdarliq IS 'Hedd asilmalari ve cihaz susmalari jurnali';
EOF

echo "01_cedveller.sql yaradildi:"
ls -la 02_db/edge/01_cedveller.sql

cd ~/Desktop/Zarat_Faza2_Zavod

cat > 02_db/edge/02_partisiyalar.sql << 'EOF'
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
EOF

echo "02_partisiyalar.sql yaradildi:"
ls -la 02_db/edge/02_partisiyalar.sql

cd ~/Desktop/Zarat_Faza2_Zavod

cat > 02_db/edge/03_seed.sql << 'EOF'
-- ============================================================
-- Baslangic melumat — sensor tipleri ve cihazlar
-- Fayl: 02_db/edge/03_seed.sql
-- ============================================================

INSERT INTO sensor_tipi (kod, ad, vahid, min_hedd, max_hedd, tesvir) VALUES
  ('TEMP',     'Temperatur',      '°C',   -5,   35,  'Silo ve anbar temperaturu'),
  ('RUTUBET',  'Rutubet',         '%',     8,   18,  'Yem qarisiginin rutubeti'),
  ('CEKI',     'Ceki (dozator)',  'kg',    0,  500,  'Dozator cixis cekisi'),
  ('VIBRASIYA','Vibrasiya',       'mm/s',  0,    7,  'Muherrik vibrasiyasi'),
  ('ENERJI',   'Elektrik yuku',   'kW',    0,   60,  'Xettin enerji serfiyyati')
ON CONFLICT (kod) DO NOTHING;

INSERT INTO cihaz (kod, sensor_tipi_kod, ad, yer, status, qurasdirilma) VALUES
  ('S001', 'TEMP',      'Silo-1 temperatur',  'Yem anbari, silo 1',    'aktiv', '2026-06-01'),
  ('S002', 'RUTUBET',   'Qarisdirici rutubet','Qarisdirma xetti',      'aktiv', '2026-06-01'),
  ('S003', 'CEKI',      'Dozator ceki',       'Dozator cixisi',        'aktiv', '2026-06-01'),
  ('S004', 'VIBRASIYA', 'Esas muherrik vib.', 'Qranulyator muherriki', 'aktiv', '2026-06-05'),
  ('S005', 'ENERJI',    'Xett enerji sayqaci','Elektrik sitasi',       'aktiv', '2026-06-05')
ON CONFLICT (kod) DO NOTHING;

SELECT c.kod, c.ad, t.ad AS tip, t.vahid, t.min_hedd, t.max_hedd
FROM cihaz c JOIN sensor_tipi t ON c.sensor_tipi_kod = t.kod
ORDER BY c.kod;
EOF

echo "03_seed.sql yaradildi:"
ls -la 02_db/edge/03_seed.sql

CREATE TABLE

psql -p 5434 -U royatalibova -d zavod_edge_db -c "
-- cedvellerin sayi
SELECT count(*) AS cedvel_sayi FROM information_schema.tables
WHERE table_schema='public';

-- test olcmesi elave edek
INSERT INTO olcme (cihaz_kod, olcme_vaxti, qiymet)
VALUES ('S001', now(), 24.3);

-- son olcmeni goster
SELECT id, cihaz_kod, olcme_vaxti, qiymet, sync_status
FROM olcme ORDER BY id DESC LIMIT 1;
"