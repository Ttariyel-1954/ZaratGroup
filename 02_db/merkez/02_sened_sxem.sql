-- ============================================================
-- Faza 3: Merkezi baza - sened, anbar, istehsal, ai sxemleri
-- Isletme sirasi:
--   psql -h Tariyels-MacBook-Pro.local -p 5432 -d zarat_erp_2
--          -f 02_db/merkez/02_sened_sxem.sql
-- ============================================================

CREATE SCHEMA IF NOT EXISTS sened;
CREATE SCHEMA IF NOT EXISTS anbar;
CREATE SCHEMA IF NOT EXISTS istehsal;
CREATE SCHEMA IF NOT EXISTS ai;

-- ============================================================
-- sened.sened — butun zavodlardan gelen senedler
-- ============================================================
CREATE TABLE IF NOT EXISTS sened.sened (
    id              BIGSERIAL PRIMARY KEY,
    zavod_kod       TEXT NOT NULL DEFAULT 'SIYEZEN',
    edge_id         BIGINT NOT NULL,

    novu            TEXT NOT NULL,
    nomre           TEXT,
    sened_tarixi    DATE,
    qarsi_teref     TEXT,
    qeyd            TEXT,
    daxil_eden      TEXT,
    menbe           TEXT,
    status          TEXT NOT NULL,
    metadata        JSONB DEFAULT '{}'::jsonb,

    yaradilma_vaxti TIMESTAMPTZ,
    deyisme_vaxti   TIMESTAMPTZ,
    qebul_vaxti     TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- IDEMPOTENTLIK — at-least-once catdirilma ucun
    CONSTRAINT sened_tek UNIQUE (zavod_kod, edge_id)
);

CREATE INDEX IF NOT EXISTS idx_m_sened_novu   ON sened.sened (novu, sened_tarixi DESC);
CREATE INDEX IF NOT EXISTS idx_m_sened_status ON sened.sened (status);
CREATE INDEX IF NOT EXISTS idx_m_sened_meta   ON sened.sened USING GIN (metadata);

-- ============================================================
-- sened.fayl
-- ============================================================
CREATE TABLE IF NOT EXISTS sened.fayl (
    id              BIGSERIAL PRIMARY KEY,
    zavod_kod       TEXT NOT NULL DEFAULT 'SIYEZEN',
    edge_id         BIGINT NOT NULL,
    sened_id        BIGINT NOT NULL REFERENCES sened.sened(id) ON DELETE CASCADE,

    orijinal_ad     TEXT NOT NULL,
    mime_tipi       TEXT NOT NULL,
    olcu_bayt       BIGINT NOT NULL,
    obyekt_acari    TEXT NOT NULL,
    sha256          TEXT NOT NULL,

    -- Merkezdeki MinIO-da hash yoxlanildimi
    sha256_yoxlandi BOOLEAN NOT NULL DEFAULT FALSE,

    qebul_vaxti     TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fayl_tek UNIQUE (zavod_kod, edge_id)
);

-- ============================================================
-- sened.versiya — sened deyisdikde kohne hal saxlanilir
-- ============================================================
CREATE TABLE IF NOT EXISTS sened.versiya (
    id              BIGSERIAL PRIMARY KEY,
    sened_id        BIGINT NOT NULL REFERENCES sened.sened(id) ON DELETE CASCADE,
    versiya_no      INT NOT NULL,
    metadata        JSONB NOT NULL,
    status          TEXT NOT NULL,
    deyisen         TEXT,
    deyisme_vaxti   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (sened_id, versiya_no)
);

-- ============================================================
-- sened.tesdiq — tesdiq marsrutu
-- ============================================================
CREATE TABLE IF NOT EXISTS sened.tesdiq (
    id              BIGSERIAL PRIMARY KEY,
    sened_id        BIGINT NOT NULL REFERENCES sened.sened(id) ON DELETE CASCADE,
    merhele         INT NOT NULL,
    rol             TEXT NOT NULL,
    tesdiq_eden     TEXT,
    qerar           TEXT,
    yorum           TEXT,
    qerar_vaxti     TIMESTAMPTZ,
    UNIQUE (sened_id, merhele)
);

-- ============================================================
-- ANBAR
-- ============================================================
CREATE TABLE IF NOT EXISTS anbar.material (
    kod             TEXT PRIMARY KEY,
    ad              TEXT NOT NULL,
    vahid           TEXT NOT NULL,
    kateqoriya      TEXT,
    min_qaliq       NUMERIC,
    aktiv           BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS anbar.herekat (
    id              BIGSERIAL PRIMARY KEY,
    zavod_kod       TEXT NOT NULL DEFAULT 'SIYEZEN',
    material_kod    TEXT NOT NULL REFERENCES anbar.material(kod),
    -- MEDAXIL (+), MEXARIC (-), INVENTAR_DUZELIS (pus)
    novu            TEXT NOT NULL,
    miqdar          NUMERIC NOT NULL,
    vahid_qiymet    NUMERIC,
    sened_id        BIGINT REFERENCES sened.sened(id),
    sifaris_id      BIGINT,
    vaxt            TIMESTAMPTZ NOT NULL DEFAULT now(),
    qeyd            TEXT,

    CONSTRAINT herekat_novu_yoxla CHECK (novu IN
        ('MEDAXIL','MEXARIC','INVENTAR_DUZELIS'))
);

CREATE INDEX IF NOT EXISTS idx_herekat_material
    ON anbar.herekat (material_kod, vaxt DESC);
CREATE INDEX IF NOT EXISTS idx_herekat_sifaris
    ON anbar.herekat (sifaris_id) WHERE sifaris_id IS NOT NULL;

-- Qaliq — hesablanan gorunus (real vaxt lazimdir, materialized deyil)
CREATE OR REPLACE VIEW anbar.qaliq AS
SELECT
    m.kod, m.ad, m.vahid, m.min_qaliq,
    coalesce(sum(
        CASE h.novu
            WHEN 'MEDAXIL'          THEN  h.miqdar
            WHEN 'MEXARIC'          THEN -h.miqdar
            WHEN 'INVENTAR_DUZELIS' THEN  h.miqdar
        END
    ), 0) AS qaliq,
    max(h.vaxt) AS son_herekat
FROM anbar.material m
LEFT JOIN anbar.herekat h ON h.material_kod = m.kod
WHERE m.aktiv
GROUP BY m.kod, m.ad, m.vahid, m.min_qaliq;

-- ============================================================
-- ISTEHSAL
-- ============================================================
CREATE TABLE IF NOT EXISTS istehsal.resept (
    kod             TEXT PRIMARY KEY,
    ad              TEXT NOT NULL,
    mehsul_vahid    TEXT NOT NULL DEFAULT 'kq',
    baza_miqdar     NUMERIC NOT NULL DEFAULT 1000,
    versiya         INT NOT NULL DEFAULT 1,
    aktiv           BOOLEAN NOT NULL DEFAULT TRUE,
    yaradilma       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS istehsal.resept_terkib (
    id              BIGSERIAL PRIMARY KEY,
    resept_kod      TEXT NOT NULL REFERENCES istehsal.resept(kod) ON DELETE CASCADE,
    material_kod    TEXT NOT NULL REFERENCES anbar.material(kod),
    miqdar          NUMERIC NOT NULL,
    dozum_faiz      NUMERIC NOT NULL DEFAULT 2,
    UNIQUE (resept_kod, material_kod)
);

CREATE TABLE IF NOT EXISTS istehsal.sifaris (
    id              BIGSERIAL PRIMARY KEY,
    zavod_kod       TEXT NOT NULL DEFAULT 'SIYEZEN',
    resept_kod      TEXT NOT NULL REFERENCES istehsal.resept(kod),
    planlanan_miqdar NUMERIC NOT NULL,
    faktiki_miqdar  NUMERIC,
    partiya_no      TEXT UNIQUE,
    status          TEXT NOT NULL DEFAULT 'planlanib',
    baslama         TIMESTAMPTZ,
    bitme           TIMESTAMPTZ,
    yaradilma       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT sifaris_status_yoxla CHECK (status IN
        ('planlanib','isleyir','bitdi','legv'))
);

-- ============================================================
-- AI
-- ============================================================
CREATE TABLE IF NOT EXISTS ai.cixaris (
    id              BIGSERIAL PRIMARY KEY,
    sened_id        BIGINT NOT NULL REFERENCES sened.sened(id) ON DELETE CASCADE,
    fayl_id         BIGINT REFERENCES sened.fayl(id),

    agent_kod       TEXT NOT NULL,
    model           TEXT NOT NULL,

    -- AI-in cixardigi struktur melumat
    netice          JSONB NOT NULL,
    -- AI-in oz eminliyi (0..1) -- sahe-sahe
    eminlik         JSONB DEFAULT '{}'::jsonb,

    -- STATUS — INSAN NEZARETI
    -- teklif -> baxilir -> tesdiqlendi | redd_edildi | duzelis_edildi
    status          TEXT NOT NULL DEFAULT 'teklif',

    -- INSAN NEYI DEYISDI — TELIM MATERIALIDIR, MUTLEQ SAXLANILIR
    insan_duzelisi  JSONB,
    baxan           TEXT,
    baxis_vaxti     TIMESTAMPTZ,

    yaradilma       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT cixaris_status_yoxla CHECK (status IN
        ('teklif','baxilir','tesdiqlendi','redd_edildi','duzelis_edildi'))
);

CREATE INDEX IF NOT EXISTS idx_cixaris_status
    ON ai.cixaris (status, yaradilma DESC);
CREATE INDEX IF NOT EXISTS idx_cixaris_sened
    ON ai.cixaris (sened_id);

CREATE TABLE IF NOT EXISTS ai.qerar (
    id              BIGSERIAL PRIMARY KEY,
    agent_kod       TEXT NOT NULL,

    sened_id        BIGINT REFERENCES sened.sened(id),
    sifaris_id      BIGINT REFERENCES istehsal.sifaris(id),
    material_kod    TEXT REFERENCES anbar.material(kod),

    seviyye         TEXT NOT NULL,
    basliq          TEXT NOT NULL,
    izah            TEXT NOT NULL,
    delil           JSONB,
    tovsiyye        JSONB,

    status          TEXT NOT NULL DEFAULT 'yeni',
    hell_eden       TEXT,
    hell_vaxti      TIMESTAMPTZ,

    yaradilma       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT qerar_seviyye_yoxla CHECK (seviyye IN ('info','xeberdarliq','kritik')),
    CONSTRAINT qerar_status_yoxla  CHECK (status  IN ('yeni','baxilir','hell_olundu','redd_edildi'))
);

CREATE INDEX IF NOT EXISTS idx_qerar_yeni
    ON ai.qerar (yaradilma DESC) WHERE status = 'yeni';

-- ============================================================
-- ai.jurnal — HER LLM CAGIRISINI QEYDE AL
-- Xerc nezareti ve sehv axtarisi ucun MUTLEQDIR.
-- ============================================================
CREATE TABLE IF NOT EXISTS ai.jurnal (
    id              BIGSERIAL PRIMARY KEY,
    agent_kod       TEXT NOT NULL,
    model           TEXT NOT NULL,
    sened_id        BIGINT,

    giris_token     INT,
    cixis_token     INT,
    muddet_ms       INT,
    ugurlu          BOOLEAN NOT NULL,
    xeta            TEXT,

    -- Eyni prompt tekrar gonderilirse kes ucun
    prompt_sha      TEXT,

    vaxt            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_jurnal_vaxt ON ai.jurnal (vaxt DESC);

-- Gunluk xerc gorunusu
CREATE OR REPLACE VIEW ai.gunluk_xerc AS
SELECT
    date_trunc('day', vaxt)::date AS gun,
    agent_kod,
    count(*)                       AS cagiris,
    sum(giris_token)               AS giris_token,
    sum(cixis_token)               AS cixis_token,
    round(avg(muddet_ms))          AS orta_ms,
    count(*) FILTER (WHERE NOT ugurlu) AS xetali
FROM ai.jurnal
GROUP BY 1, 2
ORDER BY 1 DESC, 2;

-- ============================================================
-- YOXLAMA
-- ============================================================
SELECT schemaname, count(*) AS cedvel_sayi
FROM pg_tables
WHERE schemaname IN ('sened','anbar','istehsal','ai')
GROUP BY schemaname
ORDER BY schemaname;
