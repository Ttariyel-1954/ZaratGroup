-- =============================================================================
-- ZARAT — FAZA 3 · MƏRKƏZİ BAZA SXEMLƏRİ
-- Baza: zarat_erp_2  (M4, port 5432)
-- =============================================================================
--
-- ⚠️ TAM TƏCRİD PRİNSİPİ
--
-- Bu bazada ERP komandası işləyir: inventory, production, purchase, quality,
-- finance, hr, sales, trade, logistics, asset, partner, org, system.
--
-- BU SKRIPT ONLARIN HEÇ BİR CƏDVƏLİNƏ TOXUNMUR.
-- Nə ALTER, nə DROP, nə INSERT. Yalnız YENİ sxemlər yaradılır.
--
-- Zavod sxemləri "zavod_" prefiksi ilə başlayır — qəsdən uzun,
-- ki heç kim səhvən inventory ilə qarışdırmasın.
--
--   zavod              ← MÖVCUD (Faza 2: olcme, xeberdarliq, sync_jurnal)
--   zavod_sened        ← YENİ
--   zavod_anbar        ← YENİ (ERP-nin inventory-si DEYİL)
--   zavod_istehsal     ← YENİ
--   zavod_ai           ← YENİ
--
-- Yoxlama (icra etməzdən ƏVVƏL):
--   psql -d zarat_erp_2 -c "\dn"
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- QORUYUCU: mövcud ERP sxemlərinə toxunulmadığını təsdiqləyirik
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.schemata
        WHERE schema_name IN ('anbar', 'istehsal', 'sened', 'ai')
    ) THEN
        RAISE EXCEPTION
          'DAYAN: prefiksiz sxem (anbar/istehsal/sened/ai) tapıldı. '
          'Onlar əvvəlki cəhddən qalıb — əvvəlcə silin, sonra bu skripti işlədin.';
    END IF;
END $$;


CREATE SCHEMA IF NOT EXISTS zavod_sened;
CREATE SCHEMA IF NOT EXISTS zavod_anbar;
CREATE SCHEMA IF NOT EXISTS zavod_istehsal;
CREATE SCHEMA IF NOT EXISTS zavod_ai;

COMMENT ON SCHEMA zavod_sened    IS 'Siyəzən zavodunun sənəd dövriyyəsi. ERP sənədləri ilə əlaqəsi yoxdur.';
COMMENT ON SCHEMA zavod_anbar    IS 'Zavodun ÖZ anbarı. inventory sxemi ilə QARIŞDIRMAYIN — uzlaşdırma zavod_anbar.erp_kopru vasitəsilə.';
COMMENT ON SCHEMA zavod_istehsal IS 'Zavodun reseptləri və istehsal sifarişləri. production sxemindən müstəqildir.';
COMMENT ON SCHEMA zavod_ai       IS 'AI agentlərinin çıxarışları, qərarları və çağırış jurnalı.';


-- =============================================================================
-- 1. SƏNƏD DÖVRİYYƏSİ
-- =============================================================================

CREATE TABLE IF NOT EXISTS zavod_sened.sened (
    id              BIGSERIAL PRIMARY KEY,
    zavod_kod       TEXT   NOT NULL DEFAULT 'SIYEZEN',
    edge_id         BIGINT NOT NULL,              -- edge bazasındakı id

    -- QAIME_MEDAXIL, QAIME_MEXARIC, AKT_TEHVIL, MUQAVILE, RESEPT,
    -- LAB_NETICE, EMR, SERTIFIKAT, HESAB_FAKTURA, DIGER
    novu            TEXT NOT NULL,
    nomre           TEXT,
    sened_tarixi    DATE,
    qarsi_teref     TEXT,                          -- təchizatçı / müştəri adı
    qeyd            TEXT,
    daxil_eden      TEXT,
    menbe           TEXT,                          -- FORM, FAYL, SEKIL, EPOCT, EXCEL
    status          TEXT NOT NULL,

    -- Struktur məlumat — AI çıxarışından və ya formdan
    -- {"setirler":[{"material":"...","miqdar":100,"vahid":"kq","vahid_qiymet":5.2}],
    --  "cemi_mebleg":520}
    metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,

    yaradilma_vaxti TIMESTAMPTZ,
    deyisme_vaxti   TIMESTAMPTZ,
    qebul_vaxti     TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- İDEMPOTENTLİK — at-least-once çatdırılmanın təməli.
    -- Sync eyni sənədi iki dəfə göndərsə, ikincisi UPDATE olur, dublikat YOX.
    CONSTRAINT sened_tek UNIQUE (zavod_kod, edge_id),

    CONSTRAINT sened_status_yoxla CHECK (status IN
        ('qaralama','tesdiq_gozleyir','tesdiqlendi','redd_edildi','legv'))
);

CREATE INDEX IF NOT EXISTS idx_zs_sened_novu
    ON zavod_sened.sened (novu, sened_tarixi DESC);
CREATE INDEX IF NOT EXISTS idx_zs_sened_status
    ON zavod_sened.sened (status) WHERE status <> 'legv';
CREATE INDEX IF NOT EXISTS idx_zs_sened_meta
    ON zavod_sened.sened USING GIN (metadata);
CREATE INDEX IF NOT EXISTS idx_zs_sened_qarsi
    ON zavod_sened.sened USING GIN (qarsi_teref gin_trgm_ops);


-- -----------------------------------------------------------------------------
-- FAYL — PDF, şəkil, Excel, Word
-- FAYLIN ÖZÜ BURADA DEYİL. Yalnız metadata + SHA-256.
-- Fayl MinIO-dadır. BLOB bazanı öldürür.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zavod_sened.fayl (
    id              BIGSERIAL PRIMARY KEY,
    zavod_kod       TEXT   NOT NULL DEFAULT 'SIYEZEN',
    edge_id         BIGINT NOT NULL,
    sened_id        BIGINT NOT NULL
                    REFERENCES zavod_sened.sened(id) ON DELETE CASCADE,

    orijinal_ad     TEXT   NOT NULL,               -- "qaime_2026_07_13.pdf"
    mime_tipi       TEXT   NOT NULL,
    olcu_bayt       BIGINT NOT NULL,

    -- MinIO açarı: "SIYEZEN/2026/07/13/<uuid>.pdf"
    obyekt_acari    TEXT   NOT NULL,
    sha256          TEXT   NOT NULL,

    -- Mərkəzdə TƏKRAR hesablanır. Uyğun gəlməsə → fayl korlanıb.
    sha256_yoxlandi BOOLEAN NOT NULL DEFAULT FALSE,

    qebul_vaxti     TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fayl_tek UNIQUE (zavod_kod, edge_id),
    CONSTRAINT fayl_sha_uzunluq CHECK (length(sha256) = 64),
    CONSTRAINT fayl_olcu_musbet CHECK (olcu_bayt > 0)
);

CREATE INDEX IF NOT EXISTS idx_zs_fayl_sened ON zavod_sened.fayl (sened_id);
CREATE INDEX IF NOT EXISTS idx_zs_fayl_sha   ON zavod_sened.fayl (sha256);


-- -----------------------------------------------------------------------------
-- VERSİYA — sənəd dəyişəndə köhnə hal itmir
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zavod_sened.versiya (
    id              BIGSERIAL PRIMARY KEY,
    sened_id        BIGINT NOT NULL
                    REFERENCES zavod_sened.sened(id) ON DELETE CASCADE,
    versiya_no      INT    NOT NULL,
    metadata        JSONB  NOT NULL,
    status          TEXT   NOT NULL,
    deyisen         TEXT,
    deyisme_vaxti   TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (sened_id, versiya_no)
);

-- Sənəd dəyişəndə köhnə halı avtomatik arxivləyirik
CREATE OR REPLACE FUNCTION zavod_sened.fn_versiya_saxla()
RETURNS TRIGGER AS $BODY$
DECLARE
    novbeti INT;
BEGIN
    IF OLD.metadata IS DISTINCT FROM NEW.metadata
       OR OLD.status IS DISTINCT FROM NEW.status THEN

        SELECT coalesce(max(versiya_no), 0) + 1 INTO novbeti
        FROM zavod_sened.versiya WHERE sened_id = OLD.id;

        INSERT INTO zavod_sened.versiya
            (sened_id, versiya_no, metadata, status, deyisen)
        VALUES
            (OLD.id, novbeti, OLD.metadata, OLD.status, OLD.daxil_eden);
    END IF;
    RETURN NEW;
END;
$BODY$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_zs_versiya ON zavod_sened.sened;
CREATE TRIGGER trg_zs_versiya
    BEFORE UPDATE ON zavod_sened.sened
    FOR EACH ROW
    EXECUTE FUNCTION zavod_sened.fn_versiya_saxla();


-- -----------------------------------------------------------------------------
-- TƏSDİQ MARŞRUTU
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zavod_sened.tesdiq (
    id              BIGSERIAL PRIMARY KEY,
    sened_id        BIGINT NOT NULL
                    REFERENCES zavod_sened.sened(id) ON DELETE CASCADE,
    merhele         INT    NOT NULL,               -- 1, 2, 3...
    rol             TEXT   NOT NULL,               -- anbardar, muhasib, direktor
    tesdiq_eden     TEXT,
    qerar           TEXT   NOT NULL DEFAULT 'gozleyir',
    yorum           TEXT,
    qerar_vaxti     TIMESTAMPTZ,

    UNIQUE (sened_id, merhele),
    CONSTRAINT tesdiq_qerar_yoxla CHECK (qerar IN ('gozleyir','tesdiq','redd'))
);

CREATE INDEX IF NOT EXISTS idx_zs_tesdiq_gozleyen
    ON zavod_sened.tesdiq (rol) WHERE qerar = 'gozleyir';


-- =============================================================================
-- 2. ZAVOD ANBARI
--    ⚠️ Bu, ERP-nin inventory sxemi DEYİL. Tam müstəqildir.
-- =============================================================================

CREATE TABLE IF NOT EXISTS zavod_anbar.material (
    kod             TEXT PRIMARY KEY,              -- 'QARGIDALI', 'SOYA_UNU'
    ad              TEXT NOT NULL,
    vahid           TEXT NOT NULL,                 -- kq, ton, litr, ədəd
    kateqoriya      TEXT,                          -- xammal, qablasdirma, ehtiyat
    min_qaliq       NUMERIC,                       -- bundan aşağı → xəbərdarlıq
    aktiv           BOOLEAN NOT NULL DEFAULT TRUE,
    yaradilma       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Ad üzrə fuzzy axtarış — AI qaimədə "Qarğıdalı yemi" görür,
-- bazada 'QARGIDALI' var. Uyğunlaşdırma bu indekslə işləyir.
CREATE INDEX IF NOT EXISTS idx_za_material_ad
    ON zavod_anbar.material USING GIN (ad gin_trgm_ops);


-- -----------------------------------------------------------------------------
-- ERP KÖRPÜSÜ
--
-- NİYƏ İNDİ: bu gün ERP boşdur, zavod öz anbarını qurur. Sabah ikisi
-- uzlaşdırılmalı olacaq. O gün 500 material adını əl ilə tutuşdurmaq
-- əvəzinə, uyğunluğu ELƏ İNDİ, material yarananda qeyd edirik.
--
-- Bu cədvəl HEÇ NƏYƏ TOXUNMUR — inventory.products-a FK YOXDUR.
-- Sadəcə id-ni saxlayır. ERP hazır olanda körpü qurulacaq.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zavod_anbar.erp_kopru (
    zavod_material_kod TEXT PRIMARY KEY
                       REFERENCES zavod_anbar.material(kod) ON DELETE CASCADE,

    -- inventory.products.id — QƏSDƏN FK DEYİL.
    -- ERP komandası cədvəli dəyişsə, bizim miqrasiya sınmasın.
    erp_product_id     BIGINT,
    erp_product_kod    TEXT,                       -- ERP-nin öz kodu, varsa

    uzlasdirildi       BOOLEAN NOT NULL DEFAULT FALSE,
    uzlasdiran         TEXT,
    uzlasdirma_vaxti   TIMESTAMPTZ,
    qeyd               TEXT
);

COMMENT ON TABLE zavod_anbar.erp_kopru IS
'Zavod materialı ↔ ERP məhsulu uyğunluğu. FK QOYULMAYIB: ERP hələ qurulur. Uzlaşdırma hazır olanda doldurulacaq.';


CREATE TABLE IF NOT EXISTS zavod_anbar.herekat (
    id              BIGSERIAL PRIMARY KEY,
    zavod_kod       TEXT NOT NULL DEFAULT 'SIYEZEN',
    material_kod    TEXT NOT NULL
                    REFERENCES zavod_anbar.material(kod),

    novu            TEXT    NOT NULL,              -- MEDAXIL, MEXARIC, INVENTAR_DUZELIS
    miqdar          NUMERIC NOT NULL,
    vahid_qiymet    NUMERIC,

    -- Mənbə: hansı sənəddən gəldi
    sened_id        BIGINT REFERENCES zavod_sened.sened(id),
    -- Hədəf: hansı istehsal sifarişinə sərf olundu
    sifaris_id      BIGINT,                        -- FK aşağıda əlavə olunur

    -- Kim/nə yaratdı: 'AI_TESDIQ', 'ELLE', 'INVENTAR'
    menbe           TEXT NOT NULL DEFAULT 'ELLE',

    vaxt            TIMESTAMPTZ NOT NULL DEFAULT now(),
    qeyd            TEXT,

    CONSTRAINT herekat_novu_yoxla CHECK (novu IN
        ('MEDAXIL','MEXARIC','INVENTAR_DUZELIS')),
    CONSTRAINT herekat_miqdar_musbet CHECK (miqdar > 0)
);

CREATE INDEX IF NOT EXISTS idx_za_herekat_material
    ON zavod_anbar.herekat (material_kod, vaxt DESC);
CREATE INDEX IF NOT EXISTS idx_za_herekat_sened
    ON zavod_anbar.herekat (sened_id) WHERE sened_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_za_herekat_sifaris
    ON zavod_anbar.herekat (sifaris_id) WHERE sifaris_id IS NOT NULL;


-- Qalıq — MATERIALIZED DEYİL. Anbar real vaxtda düzgün olmalıdır.
CREATE OR REPLACE VIEW zavod_anbar.qaliq AS
SELECT
    m.kod,
    m.ad,
    m.vahid,
    m.min_qaliq,
    coalesce(sum(
        CASE h.novu
            WHEN 'MEDAXIL'          THEN  h.miqdar
            WHEN 'MEXARIC'          THEN -h.miqdar
            WHEN 'INVENTAR_DUZELIS' THEN  h.miqdar
        END
    ), 0)                                     AS qaliq,
    max(h.vaxt)                               AS son_herekat,
    -- Son 30 günün orta alış qiyməti — AI qiymət anomaliyası üçün
    (SELECT round(avg(vahid_qiymet), 2)
       FROM zavod_anbar.herekat h2
      WHERE h2.material_kod = m.kod
        AND h2.novu = 'MEDAXIL'
        AND h2.vahid_qiymet IS NOT NULL
        AND h2.vaxt > now() - interval '30 days') AS orta_qiymet_30g
FROM zavod_anbar.material m
LEFT JOIN zavod_anbar.herekat h ON h.material_kod = m.kod
WHERE m.aktiv
GROUP BY m.kod, m.ad, m.vahid, m.min_qaliq;


-- =============================================================================
-- 3. İSTEHSAL
-- =============================================================================

CREATE TABLE IF NOT EXISTS zavod_istehsal.resept (
    kod             TEXT PRIMARY KEY,              -- 'YEM_BROYLER_START'
    ad              TEXT NOT NULL,
    mehsul_vahid    TEXT NOT NULL DEFAULT 'kq',
    -- Resept nə qədər məhsul üçündür (1000 kq üçün, 1 ton üçün...)
    baza_miqdar     NUMERIC NOT NULL DEFAULT 1000,
    versiya         INT NOT NULL DEFAULT 1,
    aktiv           BOOLEAN NOT NULL DEFAULT TRUE,
    yaradilma       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT resept_baza_musbet CHECK (baza_miqdar > 0)
);

CREATE TABLE IF NOT EXISTS zavod_istehsal.resept_terkib (
    id              BIGSERIAL PRIMARY KEY,
    resept_kod      TEXT NOT NULL
                    REFERENCES zavod_istehsal.resept(kod) ON DELETE CASCADE,
    material_kod    TEXT NOT NULL
                    REFERENCES zavod_anbar.material(kod),
    miqdar          NUMERIC NOT NULL,              -- baza_miqdar üçün

    -- İcazə verilən sapma faizi. Duz üçün ±5%, əsas komponent üçün ±2%.
    -- AI bunu keçən sapmanı XƏBƏRDARLIQ sayır.
    dozum_faiz      NUMERIC NOT NULL DEFAULT 2,

    UNIQUE (resept_kod, material_kod),
    CONSTRAINT terkib_miqdar_musbet CHECK (miqdar > 0),
    CONSTRAINT terkib_dozum_yoxla   CHECK (dozum_faiz >= 0 AND dozum_faiz <= 100)
);


CREATE TABLE IF NOT EXISTS zavod_istehsal.sifaris (
    id               BIGSERIAL PRIMARY KEY,
    zavod_kod        TEXT NOT NULL DEFAULT 'SIYEZEN',
    resept_kod       TEXT NOT NULL
                     REFERENCES zavod_istehsal.resept(kod),

    planlanan_miqdar NUMERIC NOT NULL,
    faktiki_miqdar   NUMERIC,
    partiya_no       TEXT UNIQUE,                  -- '2026-07-13-A'

    status           TEXT NOT NULL DEFAULT 'planlanib',
    baslama          TIMESTAMPTZ,
    bitme            TIMESTAMPTZ,
    yaradilma        TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT sifaris_status_yoxla CHECK (status IN
        ('planlanib','isleyir','bitdi','legv')),
    CONSTRAINT sifaris_miqdar_musbet CHECK (planlanan_miqdar > 0)
);

CREATE INDEX IF NOT EXISTS idx_zi_sifaris_status
    ON zavod_istehsal.sifaris (status, baslama DESC);

-- İndi FK-nı bağlaya bilərik (sifaris cədvəli yarandı)
ALTER TABLE zavod_anbar.herekat
    DROP CONSTRAINT IF EXISTS herekat_sifaris_fk;
ALTER TABLE zavod_anbar.herekat
    ADD CONSTRAINT herekat_sifaris_fk
    FOREIGN KEY (sifaris_id) REFERENCES zavod_istehsal.sifaris(id);


-- -----------------------------------------------------------------------------
-- SAPMA GÖRÜNÜŞÜ — Agent 3-ün əsas alətidir
--
-- Resept nə deyir? Faktiki nə oldu? Fərq dözüm zonasındadırmı?
-- Bu, SQL-də hesablanır. LLM YALNIZ İZAHI YAZIR.
-- Arifmetika üçün model çağırmaq həm bahalıdır, həm etibarsızdır.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW zavod_istehsal.sapma AS
WITH faktiki AS (
    SELECT sifaris_id, material_kod, sum(miqdar) AS serf
    FROM zavod_anbar.herekat
    WHERE novu = 'MEXARIC' AND sifaris_id IS NOT NULL
    GROUP BY sifaris_id, material_kod
)
SELECT
    s.id                AS sifaris_id,
    s.partiya_no,
    s.resept_kod,
    s.status,
    m.kod               AS material_kod,
    m.ad                AS material_ad,
    m.vahid,

    -- Gözlənilən: resept × istehsal nisbəti
    round(rt.miqdar * coalesce(s.faktiki_miqdar, s.planlanan_miqdar)
          / r.baza_miqdar, 2)                     AS gozlenilen,
    round(coalesce(f.serf, 0), 2)                 AS faktiki,
    round(coalesce(f.serf, 0)
          - rt.miqdar * coalesce(s.faktiki_miqdar, s.planlanan_miqdar)
            / r.baza_miqdar, 2)                   AS ferq,

    -- Sapma faizi
    CASE WHEN rt.miqdar > 0 THEN
        round(100.0 * (coalesce(f.serf, 0)
              - rt.miqdar * coalesce(s.faktiki_miqdar, s.planlanan_miqdar)
                / r.baza_miqdar)
              / (rt.miqdar * coalesce(s.faktiki_miqdar, s.planlanan_miqdar)
                 / r.baza_miqdar), 2)
    END                                           AS sapma_faiz,

    rt.dozum_faiz,

    -- HÖKM — AI bunu oxuyur, hesablamır
    CASE
        WHEN f.serf IS NULL THEN 'SERF_YOXDUR'
        WHEN rt.miqdar = 0  THEN 'NORMA'
        WHEN abs(100.0 * (f.serf - rt.miqdar * coalesce(s.faktiki_miqdar, s.planlanan_miqdar) / r.baza_miqdar)
                 / (rt.miqdar * coalesce(s.faktiki_miqdar, s.planlanan_miqdar) / r.baza_miqdar))
             <= rt.dozum_faiz THEN 'NORMA'
        WHEN f.serf > rt.miqdar * coalesce(s.faktiki_miqdar, s.planlanan_miqdar) / r.baza_miqdar
             THEN 'ARTIQ_SERF'
        ELSE 'AZ_SERF'
    END                                           AS hokm

FROM zavod_istehsal.sifaris s
JOIN zavod_istehsal.resept        r  ON r.kod  = s.resept_kod
JOIN zavod_istehsal.resept_terkib rt ON rt.resept_kod = r.kod
JOIN zavod_anbar.material         m  ON m.kod  = rt.material_kod
LEFT JOIN faktiki f ON f.sifaris_id = s.id AND f.material_kod = m.kod;


-- =============================================================================
-- 4. AI
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ÇIXARIŞ — AI nə oxudu
--
-- ⚠️ AI QƏRAR VERMİR — TƏKLİF EDİR.
-- Status 'teklif' kimi yaranır. İnsan təsdiqləməyincə anbara YAZILMIR.
-- OCR 95% dəqiqdir. Qalan 5% mühasibat sənədində fəlakətdir.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zavod_ai.cixaris (
    id              BIGSERIAL PRIMARY KEY,
    sened_id        BIGINT NOT NULL
                    REFERENCES zavod_sened.sened(id) ON DELETE CASCADE,
    fayl_id         BIGINT REFERENCES zavod_sened.fayl(id),

    agent_kod       TEXT NOT NULL,                 -- 'OCR_QAIME'
    model           TEXT NOT NULL,

    netice          JSONB NOT NULL,                -- struktur çıxarış
    -- Sahə-sahə əminlik: {"nomre":0.98,"tarix":0.95,"setirler":0.87}
    -- Panel 0.85-dən aşağı sahələri SARI fonla göstərir.
    eminlik         JSONB NOT NULL DEFAULT '{}'::jsonb,

    status          TEXT NOT NULL DEFAULT 'teklif',

    -- İNSAN NƏYİ DƏYİŞDİ — TƏLİM MATERİALIDIR, HEÇ VAXT SİLİNMİR.
    -- Altı ay sonra "AI nə qədər dəqiqdir?" sualına yeganə cavab budur.
    insan_duzelisi  JSONB,
    baxan           TEXT,
    baxis_vaxti     TIMESTAMPTZ,

    yaradilma       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT cixaris_status_yoxla CHECK (status IN
        ('teklif','baxilir','tesdiqlendi','redd_edildi','duzelis_edildi'))
);

CREATE INDEX IF NOT EXISTS idx_zai_cixaris_novbe
    ON zavod_ai.cixaris (yaradilma) WHERE status = 'teklif';
CREATE INDEX IF NOT EXISTS idx_zai_cixaris_sened
    ON zavod_ai.cixaris (sened_id);


-- -----------------------------------------------------------------------------
-- QƏRAR — AI nə aşkarladı
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zavod_ai.qerar (
    id              BIGSERIAL PRIMARY KEY,
    agent_kod       TEXT NOT NULL,                 -- 'ANBAR_MUQAYISE'

    sened_id        BIGINT REFERENCES zavod_sened.sened(id),
    sifaris_id      BIGINT REFERENCES zavod_istehsal.sifaris(id),
    material_kod    TEXT   REFERENCES zavod_anbar.material(kod),

    seviyye         TEXT NOT NULL,                 -- info, xeberdarliq, kritik
    basliq          TEXT NOT NULL,                 -- "Artıq sərfiyyat aşkarlandı"
    -- SADƏ DİLDƏ. Operator oxuyacaq — jarqon YOX.
    izah            TEXT NOT NULL,

    -- Rəqəmlər: {"gozlenilen":2200,"faktiki":2500,"ferq":300,"faiz":13.6}
    delil           JSONB,
    -- ["Anbardarla yoxlayın","Tərəzinin kalibrasiyasına baxın"]
    tovsiyye        JSONB,

    status          TEXT NOT NULL DEFAULT 'yeni',
    hell_eden       TEXT,
    hell_vaxti      TIMESTAMPTZ,
    yorum           TEXT,

    yaradilma       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT qerar_seviyye_yoxla CHECK (seviyye IN
        ('info','xeberdarliq','kritik')),
    CONSTRAINT qerar_status_yoxla CHECK (status IN
        ('yeni','baxilir','hell_olundu','redd_edildi'))
);

CREATE INDEX IF NOT EXISTS idx_zai_qerar_yeni
    ON zavod_ai.qerar (seviyye, yaradilma DESC) WHERE status = 'yeni';


-- -----------------------------------------------------------------------------
-- JURNAL — HƏR LLM ÇAĞIRIŞI
--
-- Bu cədvəl olmadan layihə BÜDCƏ İLƏ ÖLÜR.
-- Kim, nə vaxt, hansı model, neçə token, neçə saniyə, uğurlu oldumu.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zavod_ai.jurnal (
    id              BIGSERIAL PRIMARY KEY,
    agent_kod       TEXT NOT NULL,
    model           TEXT NOT NULL,
    sened_id        BIGINT,

    giris_token     INT,
    cixis_token     INT,
    muddet_ms       INT,
    ugurlu          BOOLEAN NOT NULL,
    xeta            TEXT,

    -- Eyni fayl iki dəfə emal olunmasın — keş açarı
    prompt_sha      TEXT,

    vaxt            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_zai_jurnal_vaxt  ON zavod_ai.jurnal (vaxt DESC);
CREATE INDEX IF NOT EXISTS idx_zai_jurnal_agent ON zavod_ai.jurnal (agent_kod, vaxt DESC);
CREATE INDEX IF NOT EXISTS idx_zai_jurnal_sha   ON zavod_ai.jurnal (prompt_sha)
    WHERE prompt_sha IS NOT NULL;


-- Gündəlik xərc — panel bunu göstərir, rəhbərlik bunu görür
CREATE OR REPLACE VIEW zavod_ai.gunluk_xerc AS
SELECT
    date_trunc('day', vaxt)::date      AS gun,
    agent_kod,
    count(*)                            AS cagiris,
    sum(giris_token)                    AS giris_token,
    sum(cixis_token)                    AS cixis_token,
    round(avg(muddet_ms))               AS orta_ms,
    count(*) FILTER (WHERE NOT ugurlu)  AS xetali
FROM zavod_ai.jurnal
GROUP BY 1, 2
ORDER BY 1 DESC, 2;


-- AI dəqiqliyi — insan nə qədər düzəliş edir?
-- Bu görünüş sistemin ÖZ ÜZƏRİNDƏ hesabatıdır.
CREATE OR REPLACE VIEW zavod_ai.deqiqlik AS
SELECT
    agent_kod,
    date_trunc('week', yaradilma)::date        AS hefte,
    count(*)                                    AS hamisi,
    count(*) FILTER (WHERE status = 'tesdiqlendi')    AS toxunulmadan,
    count(*) FILTER (WHERE status = 'duzelis_edildi') AS duzelis_olundu,
    count(*) FILTER (WHERE status = 'redd_edildi')    AS redd,
    round(100.0 * count(*) FILTER (WHERE status = 'tesdiqlendi')
          / nullif(count(*) FILTER (WHERE status <> 'teklif'), 0), 1)
                                                AS deqiqlik_faiz
FROM zavod_ai.cixaris
GROUP BY 1, 2
ORDER BY 2 DESC, 1;


-- =============================================================================
-- 5. SYNC JURNALI — sənəd və fayl üçün
-- =============================================================================

CREATE TABLE IF NOT EXISTS zavod_sened.sync_jurnal (
    id              BIGSERIAL PRIMARY KEY,
    zavod_kod       TEXT NOT NULL DEFAULT 'SIYEZEN',
    cedvel          TEXT NOT NULL,                 -- 'sened' | 'fayl'
    setir_sayi      INT  NOT NULL,
    yeni_setir      INT  NOT NULL,                 -- dublikat olmayan
    bayt            BIGINT,                        -- fayllar üçün
    muddet_ms       INT,
    vaxt            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_zs_sync_vaxt
    ON zavod_sened.sync_jurnal (vaxt DESC);


-- =============================================================================
-- 6. NORMALIZASIYA — Azərbaycan → ASCII, fuzzy axtarış üçün
-- =============================================================================

CREATE OR REPLACE FUNCTION zavod_anbar.normalize(t TEXT)
RETURNS TEXT AS $$
    SELECT lower(translate(t,
        'əıığĞŞşÇçÖöÜüİ',
        'eiiggSsCcOoUuI'));
$$ LANGUAGE SQL IMMUTABLE;

COMMENT ON FUNCTION zavod_anbar.normalize(TEXT) IS
  'Azərbaycan hərflərini ASCII-yə çevirir: ə→e, ı→i, ğ→g, ş→s, ç→c, ö→o, ü→u, İ→I';


-- =============================================================================
-- 7. İCAZƏLƏR — sync istifadəçisi
-- =============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zavod_sync') THEN
        GRANT USAGE ON SCHEMA zavod_sened, zavod_anbar,
                               zavod_istehsal, zavod_ai TO zavod_sync;

        GRANT SELECT, INSERT, UPDATE
            ON ALL TABLES IN SCHEMA zavod_sened TO zavod_sync;
        -- zavod_anbar: INSERT herekat üçün lazımdır (AI_TESDIQ)
        GRANT SELECT, INSERT
            ON ALL TABLES IN SCHEMA zavod_anbar TO zavod_sync;
        GRANT SELECT
            ON ALL TABLES IN SCHEMA zavod_istehsal TO zavod_sync;
        -- zavod_ai: UPDATE cixaris üçün lazımdır (tesdiq endpoint)
        GRANT SELECT, INSERT, UPDATE
            ON ALL TABLES IN SCHEMA zavod_ai TO zavod_sync;

        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA
            zavod_sened, zavod_anbar, zavod_istehsal, zavod_ai TO zavod_sync;

        -- Gələcək cədvəllər üçün
        ALTER DEFAULT PRIVILEGES IN SCHEMA zavod_sened
            GRANT SELECT, INSERT, UPDATE ON TABLES TO zavod_sync;
        ALTER DEFAULT PRIVILEGES IN SCHEMA zavod_sened, zavod_anbar,
                                           zavod_istehsal, zavod_ai
            GRANT USAGE, SELECT ON SEQUENCES TO zavod_sync;
    ELSE
        RAISE NOTICE 'zavod_sync rolu yoxdur — icazələr ötürüldü.';
    END IF;
END $$;


COMMIT;


-- =============================================================================
-- YOXLAMA
-- =============================================================================
\echo ''
\echo '=== SXEMLƏR ==='
SELECT nspname AS sxem,
       CASE WHEN nspname LIKE 'zavod%' THEN 'FAZA 2/3' ELSE 'ERP (toxunulmadı)' END AS menbe
FROM pg_namespace
WHERE nspname NOT LIKE 'pg_%' AND nspname <> 'information_schema'
ORDER BY 1;

\echo ''
\echo '=== YENİ CƏDVƏLLƏR ==='
SELECT table_schema || '.' || table_name AS cedvel
FROM information_schema.tables
WHERE table_schema IN ('zavod_sened','zavod_anbar','zavod_istehsal','zavod_ai')
  AND table_type = 'BASE TABLE'
ORDER BY 1;

\echo ''
\echo '=== GÖRÜNÜŞLƏR ==='
SELECT table_schema || '.' || table_name AS gorunus
FROM information_schema.views
WHERE table_schema LIKE 'zavod%'
ORDER BY 1;

\echo ''
\echo '=== ERP SXEMLƏRİ — TOXUNULMADIĞINI TƏSDİQ ==='
SELECT table_schema, count(*) AS cedvel_sayi
FROM information_schema.tables
WHERE table_schema IN ('inventory','production','purchase','quality',
                       'finance','hr','sales','trade','logistics',
                       'asset','partner','org','system')
GROUP BY 1 ORDER BY 1;
