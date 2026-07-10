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
