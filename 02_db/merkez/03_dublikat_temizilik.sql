-- =============================================================================
-- MİQRASİYA: Dublikat qoruması
-- Baza: zarat_erp_2  (Tariyelin MacBook-u, 192.168.1.68)
-- İcra: psql -U royatalibova -d zarat_erp_2 -f 03_dublikat_temizilik.sql
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. QƏRAR DUBLİKATLARI — hər qrupdan yalnız ən köhnəsi (min id) saxlanır
-- ---------------------------------------------------------------------------
DELETE FROM zavod_ai.qerar
WHERE status = 'yeni'
  AND id NOT IN (
    SELECT min(id)
    FROM zavod_ai.qerar
    WHERE status = 'yeni'
    GROUP BY agent_kod, basliq, coalesce(material_kod, '')
  );

\echo 'qerar: dublikatlar silindi.'

-- ---------------------------------------------------------------------------
-- 2. QƏRAR UNIKAL İNDEKS — gələcəkdə dublikat əmələ gələ bilməz
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS idx_qerar_tek
  ON zavod_ai.qerar (agent_kod, basliq, (coalesce(material_kod, '')))
  WHERE status = 'yeni';

\echo 'idx_qerar_tek: yaradıldı.'

-- ---------------------------------------------------------------------------
-- 3. ÇIXARIŞ DUBLİKATLARI — sened_id=1 üçün
--    Saxla: id=2 (tesdiqlendi), id=4 (ən son OCR teklif)
--    Sil:   id=1 (köhnə teklif), id=3 (köhnə ANBAR_MUQAYISE→cixaris yazışı)
-- ---------------------------------------------------------------------------
DELETE FROM zavod_ai.cixaris WHERE id IN (1, 3);

\echo 'cixaris: id=1,3 silindi.'

-- ---------------------------------------------------------------------------
-- 4. ÇIXARIŞ UNIKAL İNDEKS — eyni fayl iki dəfə emal olunmasın
--    sha256 fayl cədvəlindədir, cixaris-ə fayl_id vasitəsilə bağlanır.
--    Yalnız 'teklif' status üçün qoruyuruq — tesdiqlənmiş üst-üstə düşə bilər.
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS idx_cixaris_fayl_tek
  ON zavod_ai.cixaris (fayl_id, agent_kod)
  WHERE status = 'teklif' AND fayl_id IS NOT NULL;

\echo 'idx_cixaris_fayl_tek: yaradıldı.'

COMMIT;

\echo ''
\echo '=== YOXLAMA ==='
SELECT count(*) AS qerar_sayi FROM zavod_ai.qerar;
SELECT count(*) AS cixaris_sayi FROM zavod_ai.cixaris;
SELECT indexname, indexdef FROM pg_indexes
WHERE tablename IN ('qerar','cixaris') AND schemaname = 'zavod_ai'
  AND indexname LIKE 'idx_%tek%';
