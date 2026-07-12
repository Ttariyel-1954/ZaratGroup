-- ============================================================
-- Dərs 06-A: hadisə jurnalı → vəziyyət cədvəli
-- Hər (cihaz_kod, novu) üçün ən köhnə sətri saxlayır,
-- qalanlarının məlumatını ona toplayır. Data BİRLƏŞİR.
-- SIRA: 2-ci (05-dən sonra, 07-dən əvvəl)
-- ============================================================

BEGIN;

WITH aqreqat AS (
    SELECT cihaz_kod, novu,
           min(id)          AS saxlanacaq_id,
           count(*)         AS tetik_sayi,
           min(olcme_vaxti) AS acilma_vaxti,
           max(qiymet)      AS pik_qiymet
    FROM xeberdarliq
    GROUP BY cihaz_kod, novu
),
son_qiymetler AS (
    SELECT DISTINCT ON (cihaz_kod, novu)
           cihaz_kod, novu, qiymet AS son_qiymet
    FROM xeberdarliq
    ORDER BY cihaz_kod, novu, olcme_vaxti DESC
)
UPDATE xeberdarliq x
SET tetik_sayi   = a.tetik_sayi,
    acilma_vaxti = a.acilma_vaxti,
    ilk_qiymet   = x.qiymet,
    pik_qiymet   = a.pik_qiymet,
    son_qiymet   = s.son_qiymet,
    seviyye      = 'xeberdarliq'
FROM aqreqat a
JOIN son_qiymetler s ON s.cihaz_kod = a.cihaz_kod AND s.novu = a.novu
WHERE x.id = a.saxlanacaq_id;

DELETE FROM xeberdarliq
WHERE id NOT IN (
    SELECT min(id) FROM xeberdarliq GROUP BY cihaz_kod, novu
);

SELECT cihaz_kod, novu, seviyye, tetik_sayi,
       acilma_vaxti, ilk_qiymet, pik_qiymet, son_qiymet, hell_olundu
FROM xeberdarliq
ORDER BY tetik_sayi DESC;

COMMIT;
