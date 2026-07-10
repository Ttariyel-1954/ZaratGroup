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
