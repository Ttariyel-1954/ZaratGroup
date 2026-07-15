-- zavod_media: tam yeni sxem — foto/video/ses metadata (fayl MinIO-da)

CREATE SCHEMA IF NOT EXISTS zavod_media;

-- ── Media metadata ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS zavod_media.media (
    id                BIGSERIAL PRIMARY KEY,
    novu              TEXT NOT NULL,
    alt_novu          TEXT,
    bashliq           TEXT,
    obyekt_acari      TEXT NOT NULL,
    mime_tipi         TEXT NOT NULL,
    olcu_bayt         BIGINT NOT NULL,
    muddet_san        INTEGER,
    sha256            TEXT,
    sha256_yoxlandi   BOOLEAN NOT NULL DEFAULT false,
    cekilis_vaxti     TIMESTAMPTZ,
    yer               TEXT,
    cihaz_ad          TEXT,
    elaqeli_sened_id  BIGINT REFERENCES zavod_sened.sened(id),
    ai_analiz         JSONB,
    qebul_vaxti       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT media_novu_yoxla CHECK (novu IN ('FOTO','VIDEO','SES')),
    CONSTRAINT media_olcu_musbet CHECK (olcu_bayt > 0)
);

CREATE INDEX IF NOT EXISTS idx_zm_media_novu
    ON zavod_media.media (novu, qebul_vaxti DESC);
CREATE INDEX IF NOT EXISTS idx_zm_media_sened
    ON zavod_media.media (elaqeli_sened_id)
    WHERE elaqeli_sened_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_zm_media_ai
    ON zavod_media.media USING gin (ai_analiz)
    WHERE ai_analiz IS NOT NULL;

-- ── Media xulase view ─────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW zavod_media.media_ozet AS
SELECT
    novu,
    count(*)                                           AS say,
    pg_size_pretty(sum(olcu_bayt))                     AS umumi_hecm,
    sum(olcu_bayt)                                     AS umumi_bayt,
    round(avg(muddet_san))                             AS orta_muddet_san,
    count(*) FILTER (WHERE ai_analiz IS NOT NULL)      AS ai_analiz_olan
FROM zavod_media.media
GROUP BY novu
ORDER BY say DESC;

DO $$ BEGIN
    RAISE NOTICE '15_media.sql: media cedveli ve media_ozet view hazirdir';
END $$;
