-- ============================================================
-- Idempotentlik: eyni cihaz + eyni vaxt = eyni ölçmə
-- QoS 1 və retain təkrarlarını bazada həll edir.
-- Dərs 05-B
-- ============================================================

ALTER TABLE olcme
    ADD CONSTRAINT olcme_cihaz_vaxt_unikal
    UNIQUE (cihaz_kod, olcme_vaxti);
