# ==============================================================================
# ZARAT GROUP — RƏQƏMSAL ƏKİZ · YEKUN KLİENT PANELİ  (Bakı / M4)
# ==============================================================================
#
#   Siyəzən zavodunun tam rəqəmsal əkizi — 7 sxem bir ekranda.
#   Həm müxtəlif təqdimatlar (KPI, cədvəl, qrafik), həm AI köməyi.
#
#   İşə salma:
#     cd ~/Desktop/Zarat_Faza2_Zavod/10_yekun_panel
#     R --no-save -e 'shiny::runApp(".", port=4100, launch.browser=TRUE)'
#
#   Paketlər:
#     install.packages(c("shiny","bslib","DBI","RPostgres","DT","plotly",
#                        "dplyr","lubridate","glue","jsonlite","httr2"))
# ==============================================================================

Sys.setenv(OBJC_DISABLE_INITIALIZE_FORK_SAFETY = "YES")

library(shiny)
library(bslib)
library(DBI)
library(RPostgres)
library(DT)
library(plotly)
library(dplyr)
library(lubridate)
library(glue)
library(jsonlite)
suppressWarnings(suppressMessages(library(httr2)))

options(shiny.sanitize.errors = FALSE)
Sys.setlocale("LC_ALL", "en_US.UTF-8")

PANEL_VERSIYA <- "RƏQƏMSAL ƏKİZ v1"

# ==============================================================================
# KONFİQURASİYA
# ==============================================================================

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && is.na(a)) return(b)
  a
}

env_oxu <- function(yol) {
  if (!file.exists(yol)) return(list())
  s <- readLines(yol, warn = FALSE)
  s <- s[nzchar(trimws(s)) & !startsWith(trimws(s), "#")]
  nt <- list()
  for (x in strsplit(s, "=", fixed = TRUE)) {
    if (length(x) >= 2) nt[[trimws(x[1])]] <- trimws(paste(x[-1], collapse = "="))
  }
  nt
}

LAYIHE_KOK <- normalizePath("..", mustWork = FALSE)
if (!dir.exists(file.path(LAYIHE_KOK, "01_config"))) {
  LAYIHE_KOK <- normalizePath("~/Desktop/Zarat_Faza2_Zavod", mustWork = FALSE)
}
ENV <- env_oxu(file.path(LAYIHE_KOK, "01_config", ".env"))

KFG <- list(
  db = list(
    host  = "localhost",
    port  = as.integer(ENV$MERKEZ_DB_PORT %||% "5432"),
    ad    = ENV$MERKEZ_DB_NAME %||% "zarat_erp_2",
    user  = ENV$MERKEZ_DB_USER %||% Sys.info()[["user"]],
    parol = ENV$MERKEZ_DB_PASSWORD %||% ""
  ),
  zavod        = ENV$ZAVOD_KOD %||% "siyezen",
  yenilenme_ms = 6000,
  ai_url       = ENV$AI_SERVER_URL %||% "http://127.0.0.1:8100"
)

# ==============================================================================
# BAZA
# ==============================================================================

.bag <- new.env(parent = emptyenv())
.uqz <- new.env(parent = emptyenv())
BACKOFF_SAN <- 20

baza_ac <- function() {
  su <- .uqz$db %||% 0
  if (su > 0 && (as.numeric(Sys.time()) - su) < BACKOFF_SAN) return(NULL)
  cn <- .bag$db
  if (!is.null(cn) && DBI::dbIsValid(cn)) return(cn)
  cn <- tryCatch(
    DBI::dbConnect(RPostgres::Postgres(),
      host = KFG$db$host, port = KFG$db$port, dbname = KFG$db$ad,
      user = KFG$db$user, password = KFG$db$parol,
      connect_timeout = 2, bigint = "numeric"),
    error = function(e) { .uqz$db <- as.numeric(Sys.time()); NULL })
  if (!is.null(cn)) { .bag$db <- cn; .uqz$db <- 0 }
  cn
}

sorgu <- function(sql) {
  cn <- baza_ac()
  if (is.null(cn)) return(NULL)
  tryCatch(DBI::dbGetQuery(cn, sql),
           error = function(e) { message("[SQL] ", conditionMessage(e)); NULL })
}

bosdur <- function(d) is.null(d) || nrow(d) == 0

# ---- kömək ----
fr <- function(x, r = 0) {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("—")
  format(round(x, r), big.mark = " ", scientific = FALSE)
}
mb <- function(b) if (is.null(b) || is.na(b) || b == 0) "0" else sprintf("%.1f", b / 1048576)
gb <- function(b) if (is.null(b) || is.na(b) || b == 0) "0" else sprintf("%.2f", b / 1073741824)
azn <- function(x) if (is.null(x) || is.na(x)) "—" else paste0(format(round(x), big.mark = " "), " ₼")
vx_mtn <- function(y) {
  if (is.na(y)) return("—")
  if (y < 60) glue("{round(y)} san.")
  else if (y < 3600) glue("{round(y/60)} dəq.")
  else if (y < 86400) glue("{round(y/3600)} saat")
  else glue("{round(y/86400)} gün")
}
bos_hal <- function(ik, bas, alt = "") {
  div(class = "bos", div(class = "ik", ik), div(class = "bs", bas),
      if (nzchar(alt)) div(class = "al", alt))
}
bos_qrafik <- function(mtn) {
  plot_ly() |> layout(
    annotations = list(text = mtn, showarrow = FALSE,
                       font = list(size = 14, color = "#9aa8b4")),
    xaxis = list(visible = FALSE), yaxis = list(visible = FALSE),
    paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)") |>
    config(displayModeBar = FALSE)
}
bos_dt <- function(mtn) datatable(data.frame(Məlumat = mtn),
                                   options = list(dom = "t"), rownames = FALSE)
qrafik_stil <- function(p, l = 45, b = 40) {
  p |> layout(
    margin = list(l = l, r = 15, t = 12, b = b),
    paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
    xaxis = list(gridcolor = "#eae5db"), yaxis = list(gridcolor = "#eae5db")) |>
    config(displayModeBar = FALSE)
}

# ==============================================================================
# YIĞICILAR — hər sxem üçün
# ==============================================================================

# ---------- ÜMUMİ ----------
umumi_ozet <- function() {
  sorgu(glue("
    SELECT
      (SELECT count(*) FROM zavod.olcme WHERE zavod_kod='SIYEZEN')::numeric AS olcme,
      (SELECT count(*) FROM zavod_telemetriya.cihaz WHERE aktiv)::numeric AS cihaz,
      (SELECT count(*) FROM zavod_telemetriya.xeberdarliq WHERE NOT hell_olunub)::numeric AS alert,
      (SELECT count(*) FROM zavod_sened.sened)::numeric AS sened,
      (SELECT coalesce(sum(olcu_bayt),0) FROM zavod_sened.fayl)::numeric AS sened_bayt,
      (SELECT count(*) FROM zavod_media.media)::numeric AS media,
      (SELECT coalesce(sum(olcu_bayt),0) FROM zavod_media.media)::numeric AS media_bayt,
      (SELECT count(*) FROM zavod_ai.qerar WHERE status='yeni' AND seviyye='kritik')::numeric AS kritik,
      (SELECT count(*) FROM zavod_maliyye.faktura WHERE status<>'odenilib')::numeric AS odenilmemis,
      (SELECT EXTRACT(EPOCH FROM (now()-max(qebul_vaxti))) FROM zavod.olcme WHERE zavod_kod='SIYEZEN')::numeric AS gecikme"))
}

# ---------- TELEMETRİYA ----------
tel_cihazlar <- function() {
  # Real ölçmələr zavod.olcme-dədir; cihaz reyestri zavod_telemetriya.cihaz-da
  sorgu("
    WITH son AS (
      SELECT DISTINCT ON (cihaz_kod) cihaz_kod, qiymet::numeric AS qiymet, olcme_vaxti
      FROM zavod_telemetriya.olcme
      WHERE zavod='siyezen' AND olcme_vaxti > now() - interval '6 hours'
      ORDER BY cihaz_kod, olcme_vaxti DESC)
    SELECT s.cihaz_kod,
           coalesce(c.ad, s.cihaz_kod) AS ad,
           c.vahid,
           s.qiymet AS son_qiymet,
           s.olcme_vaxti,
           EXTRACT(EPOCH FROM (now()-s.olcme_vaxti))::numeric AS yas_san,
           (c.min_norma IS NOT NULL AND (s.qiymet < c.min_norma OR s.qiymet > c.max_norma)) AS norma_xarici
    FROM son s
    LEFT JOIN zavod_telemetriya.cihaz c ON c.kod = s.cihaz_kod
    ORDER BY s.cihaz_kod")
}
tel_trend <- function(saat = 6) {
  sorgu(glue("
    SELECT cihaz_kod, date_trunc('minute', olcme_vaxti) AS deq, avg(qiymet)::numeric AS orta
    FROM zavod_telemetriya.olcme
    WHERE zavod='siyezen' AND olcme_vaxti > now() - interval '{saat} hours'
    GROUP BY 1,2 ORDER BY 2"))
}
tel_alertler <- function() {
  sorgu("
    SELECT x.id, x.cihaz_kod, c.ad AS cihaz_ad, x.novu, x.seviyye,
           x.qiymet::numeric AS qiymet, x.mesaj, x.yaranma_vaxti, x.hell_olunub
    FROM zavod_telemetriya.xeberdarliq x
    LEFT JOIN zavod_telemetriya.cihaz c ON c.kod = x.cihaz_kod
    ORDER BY x.hell_olunub, x.yaranma_vaxti DESC LIMIT 30")
}

# ---------- SƏNƏD ----------
sened_ozet <- function() {
  sorgu("
    SELECT count(*)::numeric AS say,
           count(*) FILTER (WHERE status='tesdiqlendi')::numeric AS tesdiq,
           count(*) FILTER (WHERE status='tesdiq_gozleyir')::numeric AS gozleyir,
           (SELECT count(*) FROM zavod_sened.fayl)::numeric AS fayl,
           (SELECT coalesce(sum(olcu_bayt),0) FROM zavod_sened.fayl)::numeric AS bayt,
           (SELECT count(*) FROM zavod_sened.fayl WHERE sha256_yoxlandi)::numeric AS yoxlanmis
    FROM zavod_sened.sened")
}
sened_siyahi <- function() {
  sorgu("
    SELECT s.id, s.novu, s.nomre, s.sened_tarixi, s.qarsi_teref, s.status,
           s.mebleg::numeric AS mebleg, s.qebul_vaxti,
           f.orijinal_ad, f.olcu_bayt::numeric AS olcu_bayt, f.mime_tipi,
           f.sha256_yoxlandi, f.obyekt_acari
    FROM zavod_sened.sened s
    LEFT JOIN zavod_sened.fayl f ON f.sened_id = s.id
    ORDER BY s.id DESC LIMIT 50")
}
sened_novler <- function() {
  sorgu("SELECT novu, count(*)::numeric AS say FROM zavod_sened.sened GROUP BY novu ORDER BY 2 DESC")
}

# ---------- ANBAR ----------
anbar_qaliq <- function() sorgu("SELECT * FROM zavod_anbar.qaliq ORDER BY kod")
anbar_herekat <- function() {
  sorgu("
    SELECT h.vaxt, m.ad, h.novu, h.miqdar::numeric AS miqdar,
           h.vahid_qiymet::numeric AS qiymet, h.menbe
    FROM zavod_anbar.herekat h
    JOIN zavod_anbar.material m ON m.kod = h.material_kod
    ORDER BY h.vaxt DESC LIMIT 100")
}

# ---------- İSTEHSAL ----------
istehsal_sapma <- function() sorgu("SELECT * FROM zavod_istehsal.sapma ORDER BY abs(coalesce(sapma_faiz,0)) DESC")
istehsal_sifaris <- function() {
  sorgu("
    SELECT s.id, s.partiya_no, r.ad AS resept, s.planlanan_miqdar::numeric AS planlanan,
           s.faktiki_miqdar::numeric AS faktiki, s.status, s.baslama, s.bitme
    FROM zavod_istehsal.sifaris s
    JOIN zavod_istehsal.resept r ON r.kod = s.resept_kod
    ORDER BY s.yaradilma DESC")
}

# ---------- MALİYYƏ ----------
maliyye_ozet <- function() {
  sorgu("
    SELECT
      count(*) FILTER (WHERE novu='ALIS')::numeric AS alis,
      count(*) FILTER (WHERE novu='SATIS')::numeric AS satis,
      coalesce(sum(mebleg_cemi) FILTER (WHERE novu='ALIS'),0)::numeric AS alis_mebleg,
      coalesce(sum(mebleg_cemi) FILTER (WHERE novu='SATIS'),0)::numeric AS satis_mebleg,
      count(*) FILTER (WHERE status<>'odenilib')::numeric AS odenilmemis
    FROM zavod_maliyye.faktura")
}
maliyye_faktura <- function() {
  sorgu("
    SELECT id, novu, nomre, tarix, qarsi_teref,
           mebleg_cemi::numeric AS mebleg, status
    FROM zavod_maliyye.faktura ORDER BY tarix DESC, id DESC LIMIT 50")
}
maliyye_debitor <- function() sorgu("SELECT * FROM zavod_maliyye.debitor_kreditor ORDER BY abs(qaliq_borc) DESC")
maliyye_bank <- function() {
  sorgu("
    SELECT tarix, bank, novu, mebleg::numeric AS mebleg, qarsi_teref, tesvir
    FROM zavod_maliyye.bank_herekat ORDER BY tarix DESC LIMIT 50")
}

# ---------- MEDİA ----------
media_ozet <- function() sorgu("SELECT * FROM zavod_media.media_ozet ORDER BY novu")
media_siyahi <- function() {
  sorgu("
    SELECT id, novu, alt_novu, bashliq, mime_tipi, olcu_bayt::numeric AS olcu_bayt,
           muddet_san, yer, cihaz_ad, cekilis_vaxti, sha256_yoxlandi,
           (ai_analiz IS NOT NULL) AS ai_var, ai_analiz
    FROM zavod_media.media ORDER BY qebul_vaxti DESC LIMIT 50")
}

# ---------- AI ----------
ai_qerarlar <- function() {
  sorgu("
    SELECT id, agent_kod, seviyye, basliq, izah, tovsiyye::text AS tovsiyye, yaradilma
    FROM zavod_ai.qerar WHERE status='yeni'
    ORDER BY CASE seviyye WHEN 'kritik' THEN 1 WHEN 'xeberdarliq' THEN 2 ELSE 3 END,
             yaradilma DESC")
}
ai_cixarislar <- function() {
  sorgu("
    SELECT c.id, c.sened_id, c.agent_kod, c.model, c.status, c.eminlik::text AS eminlik,
           c.baxan, c.yaradilma, s.nomre, s.qarsi_teref
    FROM zavod_ai.cixaris c
    LEFT JOIN zavod_sened.sened s ON s.id = c.sened_id
    ORDER BY c.id DESC LIMIT 40")
}
ai_xerc <- function() sorgu("SELECT * FROM zavod_ai.gunluk_xerc ORDER BY gun DESC, agent_kod")
ai_deqiqlik <- function() sorgu("SELECT * FROM zavod_ai.deqiqlik ORDER BY hefte DESC")

# JSONB tövsiyə parse
tovsiyye_massiv <- function(js) {
  tryCatch({
    x <- fromJSON(js)
    if (length(x) > 0) as.character(x) else NULL
  }, error = function(e) NULL)
}

# media ikonu
media_ik <- function(novu) switch(novu %||% "", FOTO = "🖼️", VIDEO = "🎥", SES = "🎙️", "📎")

cat("Yığıcılar yükləndi\n")
# ==============================================================================
# STİL
# ==============================================================================

STIL <- '
:root{
  --grafit:#0e1620; --polad:#17222f; --xett:#26364a;
  --teal:#2dd4bf; --teal-d:#0d9488;
  --tel:#5aa9e6; --tel-d:#2c6b9e; --tel-soft:#e9f2fa;
  --min:#a78bfa; --min-d:#6d4fc4; --min-soft:#f1eefb;
  --kehreba:#f5a524; --amber-d:#b9781a;
  --yasil:#5bd08a; --yasil-d:#2f8f5b;
  --qirmizi:#e5695f; --qirmizi-d:#c0453a;
  --kagiz:#f6f4ef; --kart:#fff; --murekkeb:#16202b; --sonuk:#7a8a99;
}
body{ background:var(--kagiz); }

.ekiz-bas{
  background:radial-gradient(700px 260px at 20% -20%,rgba(45,212,191,.20),transparent 60%),
            radial-gradient(700px 260px at 82% -20%,rgba(167,139,250,.22),transparent 60%),
            linear-gradient(110deg,var(--grafit),var(--polad));
  color:#e8eef5; padding:24px 32px; display:flex; align-items:center;
  justify-content:space-between; flex-wrap:wrap; gap:18px;
}
.ekiz-bas h1{ font-family:Oswald,sans-serif; font-weight:600; font-size:32px; margin:0; color:#fff; }
.ekiz-bas .alt{ font-family:ui-monospace,Menlo,monospace; font-size:15.5px; color:#7d93a8; margin-top:5px; }
.ekiz-saat{ font-family:ui-monospace,monospace; font-size:31px; color:var(--teal); font-weight:600; text-align:right; }
.ekiz-saat .e{ display:block; font-family:Oswald,sans-serif; font-size:12.5px; color:#6a7f92;
  letter-spacing:.2em; text-transform:uppercase; margin-top:2px; }

.nabiz{ display:inline-block; width:9px; height:9px; border-radius:50%; margin-right:7px; vertical-align:middle; }
.nabiz.canli{ background:var(--yasil); animation:dow 1.7s ease-in-out infinite; }
.nabiz.gec{ background:var(--kehreba); animation:dow 1.7s ease-in-out infinite; }
.nabiz.olu{ background:var(--qirmizi); }
@keyframes dow{ 0%,100%{ box-shadow:0 0 0 0 rgba(91,208,138,.55);} 70%{ box-shadow:0 0 0 9px rgba(91,208,138,0);} }

.kpi-sira{ display:grid; grid-template-columns:repeat(auto-fit,minmax(178px,1fr)); gap:13px; padding:18px 30px 4px; }
.kpi{ background:var(--kart); border-radius:12px; padding:17px 19px; border:1px solid #e6e1d7;
  border-top:3px solid var(--teal-d); box-shadow:0 1px 3px rgba(0,0,0,.04); transition:transform .18s ease; }
.kpi:hover{ transform:translateY(-2px); box-shadow:0 6px 18px rgba(0,0,0,.08); }
.kpi.t-tel{ border-top-color:var(--tel); } .kpi.t-min{ border-top-color:var(--min); }
.kpi.t-teal{ border-top-color:var(--teal-d); } .kpi.t-kehreba{ border-top-color:var(--kehreba); }
.kpi.t-yasil{ border-top-color:var(--yasil); } .kpi.t-qirmizi{ border-top-color:var(--qirmizi); }
.kpi .l{ font-family:Oswald,sans-serif; font-size:13px; letter-spacing:.13em; text-transform:uppercase;
  color:var(--sonuk); margin-bottom:8px; }
.kpi .n{ font-family:Oswald,sans-serif; font-size:39px; font-weight:600; color:var(--murekkeb); line-height:1; }
.kpi .n .u{ font-size:17px; color:var(--sonuk); font-weight:400; margin-left:3px; }
.kpi .a{ font-size:15px; color:var(--sonuk); margin-top:6px; line-height:1.4; }

.card{ border:1px solid #e6e1d7 !important; border-radius:12px !important;
  box-shadow:0 1px 3px rgba(0,0,0,.04) !important; }
.card-header{ background:#fbfaf7 !important; border-bottom:1px solid #eae5db !important;
  font-family:Oswald,sans-serif !important; font-weight:500 !important; font-size:17px !important;
  letter-spacing:.05em !important; text-transform:uppercase !important; color:#33465a !important;
  padding:12px 18px !important; }

.cihaz-tor{ display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:12px; padding:6px 2px; }
.cihaz{ background:var(--kart); border:1px solid #e6e1d7; border-radius:10px; padding:15px 12px; text-align:center; }
.cihaz.norma{ border-left:3px solid var(--yasil); } .cihaz.asib{ border-left:3px solid var(--qirmizi); background:#fdf6f5; }
.cihaz .q{ font-family:Oswald,sans-serif; font-size:34px; font-weight:600; color:var(--murekkeb); }
.cihaz .q .u{ font-size:16px; color:var(--sonuk); }
.cihaz .ad{ font-size:15px; color:#4a5c6e; margin-top:5px; line-height:1.3; }
.cihaz .vx{ font-size:13px; color:#9aa8b4; margin-top:4px; }

.sened-k{ background:var(--kart); border:1px solid #e6e1d7; border-left:4px solid var(--min);
  border-radius:9px; padding:13px 17px; margin-bottom:9px; }
.sened-k .nom{ font-family:Oswald,sans-serif; font-size:19px; font-weight:600; }
.sened-k .det{ font-size:15.5px; color:var(--sonuk); margin-top:3px; }
.rz{ display:inline-block; padding:3px 11px; border-radius:11px; font-family:Oswald,sans-serif;
  font-size:12.5px; letter-spacing:.07em; text-transform:uppercase; white-space:nowrap; }
.rz.tesdiq{ background:#eaf7f0; color:#2f8f5b; } .rz.qaralama{ background:#f3f0e8; color:#7a6a4a; }
.rz.gozleyir{ background:#fbf3e2; color:#b9781a; } .rz.redd{ background:#fbeceb; color:#c0453a; }

.qerar{ background:var(--kart); border-radius:9px; padding:15px 19px; margin-bottom:10px;
  border:1px solid #e6e1d7; border-left:4px solid var(--sonuk); }
.qerar.kritik{ border-left-color:var(--qirmizi); background:#fdf6f5; }
.qerar.xeberdarliq{ border-left-color:var(--kehreba); background:#fdf9f0; }
.qerar.info{ border-left-color:var(--tel); }
.qerar .sv{ font-family:Oswald,sans-serif; font-size:12.5px; letter-spacing:.13em; text-transform:uppercase; margin-bottom:5px; }
.qerar.kritik .sv{ color:#c0453a; } .qerar.xeberdarliq .sv{ color:#b9781a; } .qerar.info .sv{ color:#2c6b9e; }
.qerar .bl{ font-family:Oswald,sans-serif; font-size:20px; font-weight:600; margin-bottom:5px; }
.qerar .iz{ font-size:17px; line-height:1.55; color:#3c4b5a; }
.qerar .tv{ margin-top:9px; padding-top:8px; border-top:1px solid rgba(0,0,0,.07); }
.qerar .tv-b{ font-family:Oswald,sans-serif; font-size:10px; letter-spacing:.1em; text-transform:uppercase;
  color:var(--sonuk); margin-bottom:3px; }
.qerar .tv ol{ margin:0; padding-left:18px; font-size:16px; line-height:1.6; color:#4a5c6e; }

.media-tor{ display:grid; grid-template-columns:repeat(auto-fill,minmax(235px,1fr)); gap:15px; }
.media-k{ background:var(--kart); border:1px solid #e6e1d7; border-radius:11px; overflow:hidden; }
.media-k .ust{ height:118px; display:flex; align-items:center; justify-content:center; font-size:48px;
  background:var(--min-soft); position:relative; }
.media-k .ust.video{ background:#eef0fb; } .media-k .ust.ses{ background:#f0eefb; }
.media-k .ust .mud{ position:absolute; bottom:6px; right:8px; background:rgba(14,22,32,.75); color:#fff;
  font-family:ui-monospace,monospace; font-size:10px; padding:2px 6px; border-radius:4px; }
.media-k .ust .aibadge{ position:absolute; top:6px; left:8px; background:var(--teal-d); color:#fff;
  font-family:Oswald,sans-serif; font-size:9px; letter-spacing:.06em; text-transform:uppercase;
  padding:2px 7px; border-radius:9px; }
.media-k .alt{ padding:11px 13px; }
.media-k .alt .bl{ font-family:Oswald,sans-serif; font-size:17px; font-weight:600; line-height:1.25; }
.media-k .alt .mt{ font-size:13.5px; color:var(--sonuk); margin-top:4px; font-family:ui-monospace,monospace; }

.bos{ text-align:center; padding:38px 20px; color:var(--sonuk); }
.bos .ik{ font-size:32px; opacity:.35; margin-bottom:9px; } .bos .bs{ font-family:Oswald,sans-serif;
  font-size:20px; color:#5a6b7a; margin-bottom:4px; } .bos .al{ font-size:16px; }

table.dataTable{ font-size:16px !important; }
table.dataTable thead th{ font-family:Oswald,sans-serif !important; font-weight:500 !important;
  font-size:13.5px !important; letter-spacing:.05em !important; text-transform:uppercase !important;
  background:#fbfaf7 !important; }

/* AI köməkçi */
.ai-soz{ display:flex; flex-wrap:wrap; gap:8px; margin:14px 0; }
.ai-soz button{ background:var(--tel-soft); border:1px solid #c5ddf0; color:var(--tel-d);
  border-radius:20px; padding:7px 15px; font-family:Inter,sans-serif; font-size:13px; cursor:pointer; }
.ai-soz button:hover{ background:#d8e9f7; }
.ai-cavab{ background:var(--kart); border:1px solid #e6e1d7; border-radius:11px; padding:20px 24px;
  margin-top:14px; min-height:80px; line-height:1.65; }
.ai-cavab .dusun{ color:var(--sonuk); font-style:italic; }
.ai-xulase{ font-size:20px; font-weight:700; color:var(--murekkeb);
  font-family:Oswald,sans-serif; margin-bottom:18px; line-height:1.3; }
.ai-blok{ margin-bottom:20px; }
.ai-blok-bashliq{ font-family:Oswald,sans-serif; font-size:15px; font-weight:600;
  color:var(--teal-d); letter-spacing:.08em; text-transform:uppercase;
  margin-bottom:10px; padding-bottom:6px; border-bottom:1px solid #eae5db; }
.ai-kpi-sira{ display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr));
  gap:10px; margin-bottom:4px; }
.ai-kpi-kart{ background:var(--kart); border-radius:10px; padding:14px 16px;
  border:1px solid #e6e1d7; border-top:3px solid var(--teal-d);
  box-shadow:0 1px 4px rgba(0,0,0,.04); transition:transform .15s ease; }
.ai-kpi-kart:hover{ transform:translateY(-2px); box-shadow:0 5px 14px rgba(0,0,0,.07); }
.ai-kpi-kart .l{ font-family:Oswald,sans-serif; font-size:12px; letter-spacing:.12em;
  text-transform:uppercase; color:var(--sonuk); margin-bottom:6px; }
.ai-kpi-kart .n{ font-family:Oswald,sans-serif; font-size:34px; font-weight:600;
  color:var(--murekkeb); line-height:1; }
.ai-kpi-kart .n .u{ font-size:15px; color:var(--sonuk); font-weight:400; margin-left:3px; }
.ai-metn{ background:#f8f7f4; border-left:3px solid var(--teal-d);
  border-radius:0 8px 8px 0; padding:12px 16px; font-size:14.5px; line-height:1.7; }
.ai-sual-etiket{ font-size:13px; color:var(--sonuk); margin-bottom:14px;
  font-style:italic; }
'
# ==============================================================================
# UI
# ==============================================================================

ui <- page_navbar(
  title = "ZARAT · RƏQƏMSAL ƏKİZ",
  theme = bs_theme(version = 5,
    base_font = font_google("Inter"), heading_font = font_google("Oswald"),
    primary = "#0d9488", "body-bg" = "#f6f4ef"),

  header = tagList(
    tags$head(
      tags$style(HTML(STIL)),
      tags$link(rel = "stylesheet",
        href = "https://fonts.googleapis.com/css2?family=Oswald:wght@400;500;600;700&display=swap")),
    uiOutput("basliq")
  ),

  # ------------------------------------------------------------- ÜMUMİ ----
  nav_panel("Ümumi baxış",
    uiOutput("u_kpi"),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Telemetriya trendi — son 6 saat"),
           plotlyOutput("u_trend", height = "290px")),
      card(card_header("Cihazlar — Siyəzən"), uiOutput("u_cihazlar"))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Son sənədlər"), uiOutput("u_senedler")),
      card(card_header("AI — diqqət tələb edir"), uiOutput("u_qerarlar")))
  ),

  # -------------------------------------------------------- TELEMETRİYA ----
  nav_panel("Telemetriya",
    uiOutput("t_kpi"),
    card(card_header("Cihazlar — canlı vəziyyət"), uiOutput("t_cihazlar")),
    layout_columns(col_widths = c(8, 4),
      card(card_header("Ölçmə trendi"),
        div(style = "padding:10px 16px 0;",
          selectInput("t_saat", NULL,
            choices = c("Son 1 saat"=1,"Son 6 saat"=6,"Son 24 saat"=24,"Son 3 gün"=72),
            selected = 6, width = "190px")),
        plotlyOutput("t_trend", height = "360px")),
      card(card_header("Xəbərdarlıqlar"), uiOutput("t_alertler")))
  ),

  # ------------------------------------------------------------ SƏNƏD ----
  nav_panel("Sənədlər",
    uiOutput("s_kpi"),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Sənəd siyahısı"), uiOutput("s_siyahi")),
      card(card_header("Növ üzrə bölgü"), plotlyOutput("s_novler", height = "300px"))),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Fayl bütövlüyü — SHA-256 · sətrə klikləyin"),
           DTOutput("s_fayllar")),
      card(card_header("Sənəd önizləməsi"), uiOutput("s_onizleme")))
  ),

  # ------------------------------------------------------------- ANBAR ----
  nav_panel("Anbar",
    uiOutput("a_kpi"),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Qalıqlar"), plotlyOutput("a_qrafik", height = "330px")),
      card(card_header("Material vəziyyəti"), DTOutput("a_cedvel"))),
    card(card_header("Son hərəkatlar"), DTOutput("a_herekat"))
  ),

  # ---------------------------------------------------------- İSTEHSAL ----
  nav_panel("İstehsal",
    card(card_header("Resept sapması — gözlənilən vs faktiki"),
         uiOutput("i_bos"), plotlyOutput("i_sapma", height = "320px")),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Sifarişlər"), DTOutput("i_sifaris")),
      card(card_header("Sapma detalları"), DTOutput("i_cedvel")))
  ),

  # ----------------------------------------------------------- MALİYYƏ ----
  nav_panel("Maliyyə",
    uiOutput("m_kpi"),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Fakturalar"), DTOutput("m_faktura")),
      card(card_header("Debitor / Kreditor — qalıq borc"), DTOutput("m_debitor"))),
    card(card_header("Bank hərəkatı"), DTOutput("m_bank"))
  ),

  # ------------------------------------------------------------- MEDİA ----
  nav_panel("Media",
    uiOutput("md_kpi"),
    card(card_header("Foto · Video · Səs — obyekt yaddaşı"), uiOutput("md_qalereya"))
  ),

  # ------------------------------------------------- SÜNİ İNTELLEKT ----
  nav_panel("Süni intellekt",
    uiOutput("ai_kpi"),
    layout_columns(col_widths = c(7, 5),
      card(card_header("AI qərarları"), uiOutput("ai_qerarlar")),
      card(card_header("Gündəlik çağırış"), plotlyOutput("ai_xerc", height = "260px"))),
    card(card_header("AI çıxarışları — oxunan sənədlər"), DTOutput("ai_cixarislar"))
  ),

  # -------------------------------------------------------- AI KÖMƏKÇİ ----
  nav_panel("AI Köməkçi",
    div(style = "padding:22px 30px;",
      div(style = "font-family:Oswald,sans-serif;font-size:20px;color:#33465a;margin-bottom:6px;",
          "🤖 Rəqəmsal əkiz üzrə sual verin"),
      div(style = "color:#7a8a99;font-size:14px;margin-bottom:8px;",
          "AI bazadakı bütün məlumatı görür — telemetriya, sənəd, anbar, maliyyə, istehsal."),
      uiOutput("aik_sozler"),
      textAreaInput("aik_sual", NULL, width = "100%", height = "80px",
                    placeholder = "Məsələn: Bu həftə hansı materiallar minimumdan aşağı düşüb?"),
      actionButton("aik_gonder", "Soruş", class = "btn-primary"),
      uiOutput("aik_cavab"))
  ),

  nav_spacer(),
  nav_item(uiOutput("versiya"))
)
# ==============================================================================
# SERVER
# ==============================================================================

server <- function(input, output, session) {

  taymer <- reactiveTimer(KFG$yenilenme_ms)

  d_umumi <- reactive({ taymer(); umumi_ozet() })

  # ============================ BAŞLIQ ====================================
  output$basliq <- renderUI({
    o <- d_umumi()
    gec <- if (bosdur(o)) NA else o$gecikme[1]
    v <- if (is.na(gec)) "olu" else if (gec < 300) "canli" else if (gec < 3600) "gec" else "olu"
    m <- switch(v, canli = "Rəqəmsal əkiz canlı yenilənir",
                   gec = "Telemetriya gecikir", "Zavodla əlaqə yoxdur")
    div(class = "ekiz-bas",
      div(
        h1("Siyəzən Yem Zavodu — Rəqəmsal Əkiz"),
        div(class = "alt", span(class = paste("nabiz", v)),
            glue("Zarat Group · Bakı mərkəzi · {m}"))),
      div(class = "ekiz-saat", format(Sys.time(), "%H:%M:%S"),
          span(class = "e", format(Sys.Date(), "%d.%m.%Y")))
    )
  })

  output$versiya <- renderUI({
    div(style = "font-family:ui-monospace,monospace;font-size:12px;color:#7a8a99;padding-top:9px;",
        PANEL_VERSIYA)
  })

  # ============================ ÜMUMİ BAXIŞ ================================
  output$u_kpi <- renderUI({
    o <- d_umumi()
    if (bosdur(o)) return(div(class = "kpi-sira",
      div(class = "kpi", div(class = "l", "Baza"), div(class = "n", "—"),
          div(class = "a", "Bağlantı yoxdur"))))
    div(class = "kpi-sira",
      div(class = "kpi t-tel",
        div(class = "l", "Telemetriya"), div(class = "n", fr(o$olcme[1])),
        div(class = "a", glue("{fr(o$cihaz[1])} aktiv cihaz"))),
      div(class = "kpi t-min",
        div(class = "l", "Sənəd"), div(class = "n", fr(o$sened[1])),
        div(class = "a", glue("{mb(o$sened_bayt[1])} MB fayl"))),
      div(class = "kpi t-min",
        div(class = "l", "Media"), div(class = "n", fr(o$media[1])),
        div(class = "a", glue("{gb(o$media_bayt[1])} GB foto/video/səs"))),
      div(class = if (o$kritik[1] > 0) "kpi t-qirmizi" else "kpi t-yasil",
        div(class = "l", "AI kritik"), div(class = "n", fr(o$kritik[1])),
        div(class = "a", if (o$kritik[1] > 0) "Müdaxilə lazımdır" else "Problem yoxdur")),
      div(class = if (o$alert[1] > 0) "kpi t-kehreba" else "kpi t-yasil",
        div(class = "l", "Xəbərdarlıq"), div(class = "n", fr(o$alert[1])),
        div(class = "a", "aktiv sensor həddi")),
      div(class = if (o$odenilmemis[1] > 0) "kpi t-kehreba" else "kpi t-yasil",
        div(class = "l", "Ödənilməmiş"), div(class = "n", fr(o$odenilmemis[1])),
        div(class = "a", "faktura")))
  })

  trend_qraf <- function(saat) {
    d <- tel_trend(saat)
    if (bosdur(d)) return(bos_qrafik("Telemetriya yoxdur"))
    plot_ly(d, x = ~deq, y = ~orta, color = ~cihaz_kod, type = "scatter",
            mode = "lines", line = list(width = 2)) |>
      layout(legend = list(orientation = "h", y = -0.18, font = list(size = 10)),
             hovermode = "x unified", xaxis = list(title = ""), yaxis = list(title = "")) |>
      qrafik_stil()
  }
  output$u_trend <- renderPlotly({ taymer(); trend_qraf(6) })

  cihaz_ui <- function(d) {
    if (bosdur(d)) return(bos_hal("📡", "Cihaz məlumatı yoxdur"))
    div(class = "cihaz-tor",
      lapply(seq_len(nrow(d)), function(i) {
        r <- d[i, ]
        asib <- isTRUE(r$norma_xarici)
        div(class = if (asib) "cihaz asib" else "cihaz norma",
          div(class = "q", format(round(r$son_qiymet, 1), nsmall = 1),
              span(class = "u", paste0(" ", r$vahid %||% ""))),
          div(class = "ad", r$ad %||% r$cihaz_kod),
          div(class = "vx", glue("{vx_mtn(r$yas_san)} əvvəl")))
      }))
  }
  output$u_cihazlar <- renderUI({ taymer(); cihaz_ui(tel_cihazlar()) })

  output$u_senedler <- renderUI({
    d <- sened_siyahi()
    if (bosdur(d)) return(bos_hal("📄", "Hələ sənəd yoxdur"))
    d <- head(d, 5)
    div(style = "padding:14px 18px;",
      lapply(seq_len(nrow(d)), function(i) {
        r <- d[i, ]
        rz <- switch(r$status, tesdiqlendi="tesdiq", tesdiq_gozleyir="gozleyir",
                     redd_edildi="redd", "qaralama")
        div(class = "sened-k",
          div(style = "display:flex;justify-content:space-between;gap:10px;",
            div(div(class = "nom", r$nomre %||% glue("#{r$id}")),
                div(class = "det", glue("{r$novu} · {r$qarsi_teref %||% '—'}"))),
            span(class = paste("rz", rz), r$status)))
      }))
  })

  qerar_ui <- function(d, n) {
    if (bosdur(d)) return(bos_hal("✓", "Problem aşkarlanmayıb",
                                   "AI heç bir uyğunsuzluq tapmayıb"))
    d <- head(d, n)
    div(style = "padding:14px 18px;",
      lapply(seq_len(nrow(d)), function(i) {
        r <- d[i, ]
        tv <- tovsiyye_massiv(r$tovsiyye)
        div(class = paste("qerar", r$seviyye),
          div(class = "sv", toupper(r$seviyye)),
          div(class = "bl", r$basliq),
          div(class = "iz", r$izah),
          if (!is.null(tv)) div(class = "tv",
            div(class = "tv-b", "Tövsiyə"),
            tags$ol(lapply(tv, tags$li))))
      }))
  }
  output$u_qerarlar <- renderUI({ taymer(); qerar_ui(ai_qerarlar(), 3) })

  # ============================ TELEMETRİYA ===============================
  output$t_kpi <- renderUI({
    o <- d_umumi(); c <- tel_cihazlar()
    asan <- if (bosdur(c)) 0 else sum(c$norma_xarici %in% TRUE, na.rm = TRUE)
    div(class = "kpi-sira",
      div(class = "kpi t-tel", div(class = "l", "Ümumi ölçmə"),
          div(class = "n", if (bosdur(o)) "—" else fr(o$olcme[1])),
          div(class = "a", "bütün cihazlardan")),
      div(class = "kpi t-teal", div(class = "l", "Aktiv cihaz"),
          div(class = "n", if (bosdur(o)) "—" else fr(o$cihaz[1])),
          div(class = "a", "~30 mümkün növ")),
      div(class = if (asan > 0) "kpi t-qirmizi" else "kpi t-yasil",
          div(class = "l", "Normadan kənar"), div(class = "n", fr(asan)),
          div(class = "a", if (asan > 0) "sensor həddi aşıb" else "hamısı normada")),
      div(class = if (!bosdur(o) && o$alert[1] > 0) "kpi t-kehreba" else "kpi t-yasil",
          div(class = "l", "Xəbərdarlıq"),
          div(class = "n", if (bosdur(o)) "—" else fr(o$alert[1])),
          div(class = "a", "həll gözləyir")))
  })

  output$t_cihazlar <- renderUI({ taymer(); cihaz_ui(tel_cihazlar()) })
  output$t_trend <- renderPlotly({ taymer(); trend_qraf(as.numeric(input$t_saat %||% 6)) })

  output$t_alertler <- renderUI({
    d <- tel_alertler()
    if (bosdur(d)) return(bos_hal("✓", "Xəbərdarlıq yoxdur", "Sensorlar norma daxilində"))
    div(style = "padding:6px 4px;",
      lapply(seq_len(min(nrow(d), 10)), function(i) {
        r <- d[i, ]
        rn <- if (r$seviyye == "kritik") "#c0453a" else if (r$seviyye == "xeberdarliq") "#b9781a" else "#2c6b9e"
        op <- if (isTRUE(r$hell_olunub)) "opacity:.5;" else ""
        div(style = glue("padding:10px 13px;background:#faf8f4;border-radius:8px;margin-bottom:7px;border-left:3px solid {rn};{op}"),
          div(style = "font-family:Oswald,sans-serif;font-size:13.5px;font-weight:600;",
              glue("{r$cihaz_ad %||% r$cihaz_kod}")),
          div(style = "font-size:12.5px;color:#5a6b7a;margin-top:2px;", r$mesaj %||% r$novu),
          if (isTRUE(r$hell_olunub)) div(style = "font-size:11px;color:#2f8f5b;margin-top:3px;", "✓ həll olunub"))
      }))
  })

  # ============================ SƏNƏD =====================================
  output$s_kpi <- renderUI({
    o <- sened_ozet()
    if (bosdur(o)) return(div(class = "kpi-sira", div(class = "kpi",
      div(class = "l", "Sənəd"), div(class = "n", "—"))))
    div(class = "kpi-sira",
      div(class = "kpi t-min", div(class = "l", "Ümumi sənəd"), div(class = "n", fr(o$say[1])),
          div(class = "a", "qəbul edilib")),
      div(class = "kpi t-yasil", div(class = "l", "Təsdiqlənib"), div(class = "n", fr(o$tesdiq[1])),
          div(class = "a", "mühasib təsdiqi")),
      div(class = "kpi t-kehreba", div(class = "l", "Gözləyir"), div(class = "n", fr(o$gozleyir[1])),
          div(class = "a", "təsdiq lazımdır")),
      div(class = "kpi t-teal", div(class = "l", "Fayl"), div(class = "n", fr(o$fayl[1])),
          div(class = "a", glue("{mb(o$bayt[1])} MB"))),
      div(class = "kpi t-teal", div(class = "l", "SHA-256"),
          div(class = "n", fr(o$yoxlanmis[1]), span(class = "u", glue("/{fr(o$fayl[1])}"))),
          div(class = "a", "bütövlük yoxlanıb")))
  })

  output$s_siyahi <- renderUI({
    d <- sened_siyahi()
    if (bosdur(d)) return(bos_hal("📄", "Hələ sənəd yoxdur"))
    div(style = "padding:14px 17px;max-height:420px;overflow-y:auto;",
      lapply(seq_len(min(nrow(d), 20)), function(i) {
        r <- d[i, ]
        rz <- switch(r$status, tesdiqlendi="tesdiq", tesdiq_gozleyir="gozleyir",
                     redd_edildi="redd", "qaralama")
        div(class = "sened-k",
          div(style = "display:flex;justify-content:space-between;gap:10px;",
            div(div(class = "nom", r$nomre %||% glue("#{r$id}")),
                div(class = "det", glue("{r$novu} · {r$qarsi_teref %||% '—'}")),
                if (!is.na(r$mebleg)) div(class = "det", azn(r$mebleg))),
            span(class = paste("rz", rz), r$status)))
      }))
  })

  output$s_novler <- renderPlotly({
    d <- sened_novler()
    if (bosdur(d)) return(bos_qrafik("Sənəd yoxdur"))
    plot_ly(d, x = ~say, y = ~reorder(novu, say), type = "bar", orientation = "h",
            marker = list(color = "#a78bfa"),
            hovertemplate = "%{y}: %{x}<extra></extra>") |>
      layout(xaxis = list(title = ""), yaxis = list(title = "")) |> qrafik_stil(l = 140, b = 30)
  })

  # fayllı sənədləri reaktiv saxla (seçim üçün)
  s_fayl_data <- reactive({
    d <- sened_siyahi()
    if (bosdur(d)) return(NULL)
    d[!is.na(d$orijinal_ad), , drop = FALSE]
  })

  output$s_fayllar <- renderDT({
    x <- s_fayl_data()
    if (is.null(x) || nrow(x) == 0) return(bos_dt("Fayl yoxdur"))
    y <- data.frame(
      Sened = ifelse(is.na(x$nomre), paste0("#", x$id), x$nomre),
      Fayl  = x$orijinal_ad,
      Tip   = x$mime_tipi,
      MB    = round(x$olcu_bayt / 1048576, 2),
      SHA   = ifelse(x$sha256_yoxlandi, "uygun", "gozleyir"),
      stringsAsFactors = FALSE)
    datatable(y, rownames = FALSE, selection = "single",
              options = list(dom = "tp", pageLength = 8)) |>
      formatStyle("SHA", color = styleEqual(c("uygun","gozleyir"), c("#2f8f5b","#b9781a")), fontWeight = "bold")
  })

  # seçilən sənədin faylını göstər
  output$s_onizleme <- renderUI({
    sec <- input$s_fayllar_rows_selected
    x <- s_fayl_data()
    if (is.null(sec) || length(sec) == 0 || is.null(x))
      return(div(style = "padding:34px 20px;text-align:center;color:#9aa8b4;",
                 div(style = "font-size:30px;opacity:.35;margin-bottom:9px;", "📄"),
                 div(style = "font-family:Oswald,sans-serif;font-size:18px;color:#5a6b7a;",
                     "Sətrə klikləyin"),
                 div(style = "font-size:14px;margin-top:4px;", "Faylı burada göstərəcəyəm")))
    r <- x[sec, ]
    acar <- r$obyekt_acari %||% NA

    # presigned URL al — Python skripti ilə
    url_netice <- tryCatch({
      skript <- file.path(LAYIHE_KOK, "10_yekun_panel", "fayl_url.py")
      if (!file.exists(skript)) skript <- "fayl_url.py"
      out <- system2("python3", args = c(shQuote(skript), shQuote(acar)),
                     stdout = TRUE, stderr = TRUE)
      paste(out, collapse = "\n")
    }, error = function(e) paste0("XETA\t", conditionMessage(e)))

    hisseler <- strsplit(url_netice, "\t")[[1]]
    status <- hisseler[1]

    basliq <- div(style = "padding:14px 18px;border-bottom:1px solid #eae5db;",
      div(style = "font-family:Oswald,sans-serif;font-size:18px;font-weight:600;",
          r$nomre %||% paste0("Sənəd #", r$id)),
      div(style = "font-size:13.5px;color:#7a8a99;margin-top:3px;font-family:ui-monospace,monospace;",
          glue("{r$orijinal_ad} · {round(r$olcu_bayt/1048576,2)} MB")))

    if (identical(status, "OK") && length(hisseler) >= 2) {
      url <- hisseler[2]
      mime <- r$mime_tipi %||% ""
      govde <- if (grepl("pdf", mime))
        tags$iframe(src = url, width = "100%", height = "540px",
                    style = "border:none;border-radius:0 0 11px 11px;")
      else if (grepl("image", mime))
        div(style = "padding:16px;text-align:center;",
            tags$img(src = url, style = "max-width:100%;border-radius:8px;"))
      else
        div(style = "padding:24px;text-align:center;",
            tags$a(href = url, target = "_blank", class = "btn btn-primary", "Faylı aç"))
      tagList(basliq, govde)
    } else {
      sebeb <- if (length(hisseler) >= 2) hisseler[2] else "naməlum"
      tagList(basliq,
        div(style = "padding:28px 22px;text-align:center;",
          div(style = "font-size:26px;margin-bottom:10px;", "🔓"),
          div(style = "font-family:Oswald,sans-serif;font-size:16px;color:#b9781a;margin-bottom:6px;",
              "Fayl MinIO-da tapılmadı"),
          div(style = "font-size:13.5px;color:#7a8a99;line-height:1.5;",
              "Bu, seed (sınaq) məlumatıdır — real fayl hələ yüklənməyib. Real sənəd gələndə burada açılacaq."),
          div(style = "font-size:11.5px;color:#9aa8b4;margin-top:10px;font-family:ui-monospace,monospace;",
              sebeb)))
    }
  })
  # ============================ ANBAR =====================================
  output$a_kpi <- renderUI({
    d <- anbar_qaliq()
    if (bosdur(d)) return(div(class = "kpi-sira", div(class = "kpi",
      div(class = "l", "Anbar"), div(class = "n", "—"))))
    say <- nrow(d); dolu <- sum(d$qaliq > 0, na.rm = TRUE)
    az <- sum(!is.na(d$min_qaliq) & d$qaliq < d$min_qaliq & d$qaliq >= 0)
    mnf <- sum(d$qaliq < 0, na.rm = TRUE)
    div(class = "kpi-sira",
      div(class = "kpi t-teal", div(class = "l", "Material"), div(class = "n", fr(say)),
          div(class = "a", glue("{fr(dolu)} qalıq var"))),
      div(class = if (az > 0) "kpi t-kehreba" else "kpi t-yasil",
          div(class = "l", "Minimumdan aşağı"), div(class = "n", fr(az)),
          div(class = "a", if (az > 0) "sifariş lazımdır" else "normadadır")),
      div(class = if (mnf > 0) "kpi t-qirmizi" else "kpi t-yasil",
          div(class = "l", "Mənfi qalıq"), div(class = "n", fr(mnf)),
          div(class = "a", if (mnf > 0) "uyğunsuzluq!" else "yoxdur")))
  })

  output$a_qrafik <- renderPlotly({
    d <- anbar_qaliq()
    if (bosdur(d)) return(bos_qrafik("Anbar boşdur"))
    d$reng <- ifelse(d$qaliq < 0, "#e5695f",
              ifelse(!is.na(d$min_qaliq) & d$qaliq < d$min_qaliq, "#f5a524", "#2dd4bf"))
    plot_ly(d, x = ~qaliq, y = ~reorder(ad, qaliq), type = "bar", orientation = "h",
            marker = list(color = ~reng), hovertemplate = "%{y}: %{x}<extra></extra>") |>
      layout(xaxis = list(title = "", zerolinecolor = "#b8b0a2"), yaxis = list(title = ""),
             showlegend = FALSE) |> qrafik_stil(l = 105)
  })

  output$a_cedvel <- renderDT({
    d <- anbar_qaliq()
    if (bosdur(d)) return(bos_dt("Anbar boşdur"))
    y <- data.frame(
      Kod = d$kod, Material = d$ad, Qaliq = round(d$qaliq, 1), Vahid = d$vahid,
      Minimum = ifelse(is.na(d$min_qaliq), 0, d$min_qaliq),
      Veziyyet = ifelse(d$qaliq < 0, "MENFI",
                 ifelse(!is.na(d$min_qaliq) & d$qaliq < d$min_qaliq, "AZ", "Normal")),
      stringsAsFactors = FALSE)
    datatable(y, rownames = FALSE, options = list(dom = "t", pageLength = 25)) |>
      formatStyle("Veziyyet", color = styleEqual(c("MENFI","AZ","Normal"),
                  c("#c0453a","#b9781a","#2f8f5b")), fontWeight = "bold")
  })

  output$a_herekat <- renderDT({
    d <- anbar_herekat()
    if (bosdur(d)) return(bos_dt("Hərəkat yoxdur"))
    y <- data.frame(
      Vaxt = format(d$vaxt, "%d.%m %H:%M"), Material = d$ad, Nov = d$novu,
      Miqdar = round(d$miqdar, 1),
      Qiymet = ifelse(is.na(d$qiymet), "—", format(round(d$qiymet, 2), nsmall = 2)),
      Menbe = d$menbe, stringsAsFactors = FALSE)
    datatable(y, rownames = FALSE, options = list(dom = "tp", pageLength = 10)) |>
      formatStyle("Nov", color = styleEqual(c("MEDAXIL","MEXARIC","INVENTAR_DUZELIS"),
                  c("#2f8f5b","#c0453a","#2c6b9e")), fontWeight = "bold")
  })

  # ============================ İSTEHSAL ==================================
  sapma_r <- reactive({ taymer(); istehsal_sapma() })

  output$i_bos <- renderUI({
    if (bosdur(sapma_r())) bos_hal("⚙️", "İstehsal sifarişi yoxdur",
                                    "Resept və sifariş daxil ediləndə görünəcək")
  })
  output$i_sapma <- renderPlotly({
    d <- sapma_r()
    if (bosdur(d)) return(bos_qrafik(""))
    d$reng <- ifelse(d$hokm == "NORMA", "#2dd4bf",
              ifelse(d$hokm == "ARTIQ_SERF", "#e5695f", "#f5a524"))
    plot_ly(d, x = ~sapma_faiz, y = ~material_ad, type = "bar", orientation = "h",
            marker = list(color = ~reng), hovertemplate = "%{y}: %{x:.1f}%<extra></extra>") |>
      layout(xaxis = list(title = "sapma %", zerolinecolor = "#8a9aa8"),
             yaxis = list(title = ""), showlegend = FALSE) |> qrafik_stil(l = 115)
  })
  output$i_sifaris <- renderDT({
    d <- istehsal_sifaris()
    if (bosdur(d)) return(bos_dt("Sifariş yoxdur"))
    y <- data.frame(
      Partiya = d$partiya_no %||% "—", Resept = d$resept,
      Planlanan = round(d$planlanan, 0),
      Faktiki = ifelse(is.na(d$faktiki), "—", round(d$faktiki, 0)),
      Status = d$status, stringsAsFactors = FALSE)
    datatable(y, rownames = FALSE, options = list(dom = "tp", pageLength = 8))
  })
  output$i_cedvel <- renderDT({
    d <- sapma_r()
    if (bosdur(d)) return(bos_dt("Sapma yoxdur"))
    y <- data.frame(
      Material = d$material_ad, Gozlenilen = round(d$gozlenilen, 1),
      Faktiki = round(d$faktiki, 1), Ferq = round(d$ferq, 1),
      Sapma = round(d$sapma_faiz, 1), Hokm = d$hokm, stringsAsFactors = FALSE)
    datatable(y, rownames = FALSE, options = list(dom = "tp", pageLength = 8)) |>
      formatStyle("Hokm", color = styleEqual(c("NORMA","ARTIQ_SERF","AZ_SERF"),
                  c("#2f8f5b","#c0453a","#b9781a")), fontWeight = "bold")
  })

  # ============================ MALİYYƏ ===================================
  output$m_kpi <- renderUI({
    o <- maliyye_ozet()
    if (bosdur(o)) return(div(class = "kpi-sira", div(class = "kpi",
      div(class = "l", "Maliyyə"), div(class = "n", "—"))))
    div(class = "kpi-sira",
      div(class = "kpi t-tel", div(class = "l", "Alış fakturası"), div(class = "n", fr(o$alis[1])),
          div(class = "a", azn(o$alis_mebleg[1]))),
      div(class = "kpi t-yasil", div(class = "l", "Satış fakturası"), div(class = "n", fr(o$satis[1])),
          div(class = "a", azn(o$satis_mebleg[1]))),
      div(class = if (o$odenilmemis[1] > 0) "kpi t-kehreba" else "kpi t-yasil",
          div(class = "l", "Ödənilməmiş"), div(class = "n", fr(o$odenilmemis[1])),
          div(class = "a", "faktura")))
  })
  output$m_faktura <- renderDT({
    d <- maliyye_faktura()
    if (bosdur(d)) return(bos_dt("Faktura yoxdur"))
    y <- data.frame(
      Nomre = d$nomre %||% paste0("#", d$id), Nov = d$novu,
      Tarix = format(d$tarix, "%d.%m.%y"), Teref = d$qarsi_teref,
      Mebleg = round(d$mebleg, 0), Status = d$status, stringsAsFactors = FALSE)
    datatable(y, rownames = FALSE, options = list(dom = "tp", pageLength = 8)) |>
      formatStyle("Status", color = styleEqual(c("odenilib","qismen","odenilmeyib"),
                  c("#2f8f5b","#b9781a","#c0453a")), fontWeight = "bold") |>
      formatCurrency("Mebleg", currency = " ₼", before = FALSE, digits = 0, mark = " ")
  })
  output$m_debitor <- renderDT({
    d <- maliyye_debitor()
    if (bosdur(d)) return(bos_dt("Borc məlumatı yoxdur"))
    nm <- names(d)
    y <- data.frame(
      Teref = d[[grep("teref", nm, value = TRUE)[1]]],
      Faktura = round(d[[grep("faktura", nm, value = TRUE)[1]]] %||% 0, 0),
      Odenis = round(d[[grep("odenis", nm, value = TRUE)[1]]] %||% 0, 0),
      Qaliq = round(d[[grep("qaliq", nm, value = TRUE)[1]]] %||% 0, 0),
      stringsAsFactors = FALSE)
    datatable(y, rownames = FALSE, options = list(dom = "tp", pageLength = 8)) |>
      formatCurrency(c("Faktura","Odenis","Qaliq"), currency = " ₼", before = FALSE, digits = 0, mark = " ")
  })
  output$m_bank <- renderDT({
    d <- maliyye_bank()
    if (bosdur(d)) return(bos_dt("Bank hərəkatı yoxdur"))
    y <- data.frame(
      Tarix = format(d$tarix, "%d.%m.%y"), Bank = d$bank, Nov = d$novu,
      Mebleg = round(d$mebleg, 0), Teref = d$qarsi_teref %||% "—",
      Tesvir = substr(d$tesvir %||% "", 1, 40), stringsAsFactors = FALSE)
    datatable(y, rownames = FALSE, options = list(dom = "tp", pageLength = 10)) |>
      formatStyle("Nov", color = styleEqual(c("MEDAXIL","MEXARIC"), c("#2f8f5b","#c0453a")), fontWeight = "bold") |>
      formatCurrency("Mebleg", currency = " ₼", before = FALSE, digits = 0, mark = " ")
  })

  # ============================ MEDİA =====================================
  output$md_kpi <- renderUI({
    o <- media_ozet()
    if (bosdur(o)) return(div(class = "kpi-sira", div(class = "kpi",
      div(class = "l", "Media"), div(class = "n", "—"))))
    nm <- names(o)
    say_s  <- grep("say|count|adet", nm, value = TRUE)[1]
    bayt_s <- grep("bayt|hecm|olcu|umumi", nm, value = TRUE)[1]
    kart <- lapply(seq_len(nrow(o)), function(i) {
      r <- o[i, ]
      say_v <- if (!is.na(say_s)) r[[say_s]] else NA
      hecm  <- if (!is.na(bayt_s)) glue("{gb(r[[bayt_s]])} GB") else ""
      div(class = "kpi t-min",
        div(class = "l", r$novu %||% "Media"),
        div(class = "n", fr(say_v)),
        div(class = "a", hecm))
    })
    div(class = "kpi-sira", kart)
  })
  output$md_qalereya <- renderUI({
    d <- media_siyahi()
    if (bosdur(d)) return(bos_hal("🖼️", "Media yoxdur", "Foto/video/səs yükləndikdə görünəcək"))
    div(class = "media-tor",
      lapply(seq_len(nrow(d)), function(i) {
        r <- d[i, ]
        ust_kl <- switch(r$novu %||% "", VIDEO = "video", SES = "ses", "")
        mud <- if (!is.na(r$muddet_san)) sprintf("%d:%02d", r$muddet_san %/% 60, r$muddet_san %% 60) else NULL
        ai_mtn <- NULL
        if (isTRUE(r$ai_var)) {
          ai_mtn <- tryCatch({
            a <- fromJSON(r$ai_analiz)
            a$xulase %||% a$netice %||% a$summary %||% "AI analiz edib"
          }, error = function(e) "AI analiz edib")
        }
        div(class = "media-k",
          div(class = paste("ust", ust_kl), media_ik(r$novu),
            if (isTRUE(r$ai_var)) span(class = "aibadge", "AI ✓"),
            if (!is.null(mud)) span(class = "mud", mud)),
          div(class = "alt",
            div(class = "bl", r$bashliq %||% r$alt_novu %||% r$novu),
            div(class = "mt", glue("{mb(r$olcu_bayt)} MB · {r$yer %||% '—'}")),
            if (!is.null(ai_mtn)) div(style = "font-size:11.5px;color:#0d9488;margin-top:5px;", ai_mtn)))
      }))
  })

  # ============================ SÜNİ İNTELLEKT ============================
  output$ai_kpi <- renderUI({
    x <- ai_xerc(); c <- ai_cixarislar(); q <- ai_qerarlar(); dq <- ai_deqiqlik()
    cag <- if (bosdur(x)) 0 else sum(x[[grep("cagiris", names(x), value = TRUE)[1]]] %||% 0, na.rm = TRUE)
    cix <- if (bosdur(c)) 0 else nrow(c)
    krt <- if (bosdur(q)) 0 else sum(q$seviyye == "kritik")
    deq <- NA
    if (!bosdur(dq)) {
      dcol <- grep("deqiq|faiz", names(dq), value = TRUE)[1]
      if (!is.na(dcol)) deq <- dq[[dcol]][1]
    }
    div(class = "kpi-sira",
      div(class = "kpi t-min", div(class = "l", "AI çağırışı"), div(class = "n", fr(cag)),
          div(class = "a", "sənəd emalı")),
      div(class = "kpi t-teal", div(class = "l", "Oxunan sənəd"), div(class = "n", fr(cix)),
          div(class = "a", "strukturlaşdırılıb")),
      div(class = "kpi t-yasil", div(class = "l", "Dəqiqlik"),
          div(class = "n", if (is.na(deq)) "—" else glue("{round(deq)}%")),
          div(class = "a", "düzəlişsiz təsdiq")),
      div(class = if (krt > 0) "kpi t-qirmizi" else "kpi t-yasil",
          div(class = "l", "Kritik tapıntı"), div(class = "n", fr(krt)),
          div(class = "a", if (krt > 0) "müdaxilə lazımdır" else "problem yoxdur")))
  })
  output$ai_qerarlar <- renderUI({ taymer(); qerar_ui(ai_qerarlar(), 12) })
  output$ai_xerc <- renderPlotly({
    d <- ai_xerc()
    if (bosdur(d)) return(bos_qrafik("AI hələ işləməyib"))
    gc <- grep("gun", names(d), value = TRUE)[1]
    cc <- grep("cagiris", names(d), value = TRUE)[1]
    ac <- grep("agent", names(d), value = TRUE)[1]
    if (any(is.na(c(gc, cc)))) return(bos_qrafik("Xərc məlumatı yoxdur"))
    p <- if (!is.na(ac)) plot_ly(d, x = d[[gc]], y = d[[cc]], color = d[[ac]], type = "bar")
         else plot_ly(d, x = d[[gc]], y = d[[cc]], type = "bar", marker = list(color = "#a78bfa"))
    p |> layout(barmode = "stack", xaxis = list(title = ""), yaxis = list(title = "çağırış"),
                legend = list(orientation = "h", y = -0.22, font = list(size = 10))) |>
      qrafik_stil(b = 55)
  })
  output$ai_cixarislar <- renderDT({
    d <- ai_cixarislar()
    if (bosdur(d)) return(bos_dt("AI hələ sənəd oxumayıb"))
    y <- data.frame(
      Sened = ifelse(is.na(d$nomre), paste0("#", d$sened_id), d$nomre),
      Agent = d$agent_kod, Model = d$model, Status = d$status,
      Baxan = ifelse(is.na(d$baxan), "—", d$baxan),
      Vaxt = format(d$yaradilma, "%d.%m %H:%M"), stringsAsFactors = FALSE)
    datatable(y, rownames = FALSE, options = list(dom = "tp", pageLength = 8)) |>
      formatStyle("Status", color = styleEqual(
        c("teklif","tesdiqlendi","duzelis_edildi","redd_edildi"),
        c("#b9781a","#2f8f5b","#2c6b9e","#c0453a")), fontWeight = "bold")
  })

  # ============================ AI KÖMƏKÇİ — YARDIMCILAR ==================

  ai_reng <- function(ad) {
    switch(ad %||% "teal",
      teal      = "#0d9488",
      mavi      = "#5aa9e6",
      benovseyi = "#a78bfa",
      yasil     = "#5bd08a",
      kehreba   = "#f5a524",
      qirmizi   = "#e5695f",
      "#0d9488")
  }

  ai_blok_plotly <- function(b) {
    tip <- b$tip %||% ""
    if (tip == "bar") {
      x_vals <- unlist(b$x %||% list())
      y_vals <- as.numeric(unlist(b$y %||% list()))
      reng   <- ai_reng(b$reng %||% "teal")
      vahid  <- b$vahid %||% ""
      p <- plot_ly(x = x_vals, y = y_vals, type = "bar",
                   marker = list(color = reng),
                   hovertemplate = paste0("%{x}: %{y} ", vahid, "<extra></extra>"))
      qrafik_stil(p)

    } else if (tip == "xett") {
      x_vals    <- unlist(b$x %||% list())
      seriyalar <- b$seriyalar %||% list()
      vahid     <- b$vahid %||% ""
      p <- plot_ly()
      for (s in seriyalar) {
        y_vals <- as.numeric(unlist(s$y %||% list()))
        p <- add_trace(p, x = x_vals, y = y_vals, name = s$ad %||% "",
                       type = "scatter", mode = "lines+markers",
                       hovertemplate = paste0("%{x}: %{y} ", vahid, "<extra></extra>"))
      }
      qrafik_stil(p) |> layout(legend = list(orientation = "h", y = -0.25))

    } else if (tip == "pie") {
      etiketler <- unlist(b$etiketler %||% list())
      qiymetler <- as.numeric(unlist(b$qiymetler %||% list()))
      plot_ly(labels = etiketler, values = qiymetler, type = "pie",
              hole = 0.4, textposition = "inside",
              hovertemplate = "%{label}: %{value} (%{percent})<extra></extra>",
              marker = list(colors = c("#0d9488","#5aa9e6","#a78bfa",
                                       "#5bd08a","#f5a524","#e5695f"))) |>
        layout(paper_bgcolor = "rgba(0,0,0,0)",
               showlegend = TRUE,
               legend = list(orientation = "h")) |>
        config(displayModeBar = FALSE)

    } else if (tip == "qauge") {
      val   <- as.numeric(b$qiymet %||% 0)
      mini  <- as.numeric(b$min    %||% 0)
      maxi  <- as.numeric(b$max    %||% 100)
      vahid <- b$vahid %||% ""
      araliq <- maxi - mini
      plot_ly(type = "indicator", mode = "gauge+number",
              value = val,
              number = list(suffix = paste0(" ", vahid),
                            font   = list(size = 36, color = "#16202b")),
              gauge = list(
                axis  = list(range = list(mini, maxi)),
                bar   = list(color = ai_reng("teal")),
                steps = list(
                  list(range = c(mini, mini + araliq * 0.5), color = "#f0f7f4"),
                  list(range = c(mini + araliq * 0.5, mini + araliq * 0.8),
                       color = "#d0eee8")
                ),
                threshold = list(
                  line      = list(color = ai_reng("kehreba"), width = 3),
                  thickness = 0.75,
                  value     = mini + araliq * 0.8
                )
              )) |>
        layout(margin = list(l = 20, r = 20, t = 50, b = 20),
               paper_bgcolor = "rgba(0,0,0,0)") |>
        config(displayModeBar = FALSE)

    } else {
      bos_qrafik("Diaqram tipi tanınmır")
    }
  }

  ai_kpi_blok <- function(b) {
    data_list <- b$data %||% list()
    div(class = "ai-kpi-sira",
      lapply(data_list, function(kart) {
        reng  <- ai_reng(kart$reng %||% "teal")
        vahid <- kart$vahid %||% ""
        div(class = "ai-kpi-kart",
          style = paste0("border-top-color:", reng, ";"),
          div(class = "l", kart$etiket %||% ""),
          div(class = "n", kart$qiymet %||% "—",
            if (nzchar(vahid)) tags$span(class = "u", vahid))
        )
      })
    )
  }

  ai_cedvel_blok <- function(b) {
    sutunlar <- as.character(unlist(b$sutunlar %||% list()))
    setirler <- b$setirler %||% list()
    if (length(sutunlar) == 0 && length(setirler) == 0)
      return(div(class = "ai-metn", "Cədvəl məlumatı yoxdur."))
    tags$div(class = "table-responsive", style = "margin-top:4px;",
      tags$table(class = "table table-sm table-hover table-bordered",
        style = "font-size:13.5px;",
        if (length(sutunlar) > 0)
          tags$thead(tags$tr(lapply(sutunlar, function(s) tags$th(s)))),
        tags$tbody(lapply(setirler, function(row) {
          tags$tr(lapply(as.list(unlist(row)), function(cell)
            tags$td(as.character(cell))))
        }))
      )
    )
  }

  ai_metn_blok <- function(b) {
    div(class = "ai-metn", b$data %||% "")
  }

  ai_blok_ui <- function(b, i) {
    tip <- b$tip %||% "metn"
    icerik <- if (tip %in% c("bar", "xett", "pie", "qauge")) {
      plotlyOutput(paste0("ai_plt_", i), height = "300px")
    } else if (tip == "kpi") {
      ai_kpi_blok(b)
    } else if (tip == "cedvel") {
      ai_cedvel_blok(b)
    } else {
      ai_metn_blok(b)
    }
    div(class = "ai-blok",
      if (nzchar(b$basliq %||% ""))
        div(class = "ai-blok-bashliq", b$basliq),
      icerik
    )
  }

  # ============================ AI KÖMƏKÇİ ================================
  hazir_suallar <- c(
    "Hansı materiallar minimumdan aşağıdır?",
    "Bu həftə neçə sənəd təsdiqlənib?",
    "Ən böyük ödənilməmiş faktura hansıdır?",
    "AI hansı kritik problemləri tapıb?")

  output$aik_sozler <- renderUI({
    div(class = "ai-soz",
      lapply(seq_along(hazir_suallar), function(i) {
        actionButton(paste0("aik_haz_", i), hazir_suallar[i], class = "aik-haz")
      }))
  })
  lapply(seq_along(hazir_suallar), function(i) {
    observeEvent(input[[paste0("aik_haz_", i)]], {
      updateTextAreaInput(session, "aik_sual", value = hazir_suallar[i])
    })
  })

  aik_netice <- reactiveVal(NULL)
  observeEvent(input$aik_gonder, {
    sual <- trimws(input$aik_sual %||% "")
    if (!nzchar(sual)) return()
    aik_netice(list(veziyyet = "dusunur", sual = sual))

    # Bazadan kontekst yığ (AI-a real data ver)
    kontekst <- tryCatch({
      q <- anbar_qaliq(); s <- sened_ozet(); m <- maliyye_ozet(); qr <- ai_qerarlar()
      list(
        anbar = if (!bosdur(q)) q[, c("kod","ad","qaliq","min_qaliq")] else NULL,
        sened = if (!bosdur(s)) as.list(s) else NULL,
        maliyye = if (!bosdur(m)) as.list(m) else NULL,
        qerarlar = if (!bosdur(qr)) qr[, c("seviyye","basliq","izah")] else NULL)
    }, error = function(e) NULL)

    cavab_data <- tryCatch({
      req_body <- list(
        sual = sual,
        kontekst = toJSON(kontekst, auto_unbox = TRUE, null = "null"))
      resp <- request(paste0(KFG$ai_url, "/komekci/sual")) |>
        req_body_json(req_body) |>
        req_timeout(60) |>
        req_perform()
      cnt <- resp_body_json(resp, simplifyVector = FALSE)
      if (!is.null(cnt$xulase)) {
        cnt
      } else if (!is.null(cnt$cavab)) {
        list(xulase = cnt$cavab, bloklar = list())
      } else {
        list(xulase = "AI cavab qaytarmadi.", bloklar = list())
      }
    }, error = function(e) {
      list(xulase = paste0("__XETA__:", conditionMessage(e)),
           bloklar = list(), xeta = TRUE)
    })
    aik_netice(list(veziyyet = "hazir", sual = sual, cavab = cavab_data))
  })

  # Plotly diaqramlarini dinamik qurur (renderUI ile sinxron)
  observeEvent(aik_netice(), {
    n <- aik_netice()
    if (is.null(n) || !identical(n$veziyyet, "hazir")) return()
    bloklar <- n$cavab$bloklar %||% list()
    lapply(seq_along(bloklar), function(i) {
      b <- bloklar[[i]]
      if ((b$tip %||% "") %in% c("bar", "xett", "pie", "qauge")) {
        local({
          li <- i; lb <- b
          output[[paste0("ai_plt_", li)]] <- renderPlotly({ ai_blok_plotly(lb) })
        })
      }
    })
  }, ignoreNULL = TRUE)

  output$aik_cavab <- renderUI({
    n <- aik_netice()
    if (is.null(n)) {
      return(div(class = "ai-cavab",
        span(class = "dusun",
             "Sualinizi yazin ve ya yuxaridaki hazir suallardan secin.")))
    }
    if (identical(n$veziyyet, "dusunur")) {
      return(div(class = "ai-cavab",
        span(class = "dusun", "Dusunurem... (AI servere muraciet edilir)")))
    }

    cd <- n$cavab
    # Xeta hali
    if (isTRUE(cd$xeta) || startsWith(cd$xulase %||% "", "__XETA__:")) {
      xeta_mtn <- sub("^__XETA__:", "", cd$xulase %||% "bilinmeyen xeta")
      return(div(class = "ai-cavab",
        div(style = "color:#b9781a;font-weight:600;margin-bottom:6px;",
            "AI komekci hazir deyil"),
        div(style = "font-size:13.5px;color:#5a6b7a;",
            glue("Server cavab vermir ({KFG$ai_url}). AI serveri ise salmalidir.")),
        div(style = "font-size:12px;color:#9aa8b4;margin-top:8px;font-family:ui-monospace,monospace;",
            xeta_mtn)))
    }

    bloklar <- cd$bloklar %||% list()
    div(class = "ai-cavab",
      # Sual etiket
      div(class = "ai-sual-etiket", paste0("« ", n$sual, " »")),
      # Xulase
      if (nzchar(cd$xulase %||% ""))
        div(class = "ai-xulase", cd$xulase),
      # Bloklar
      if (length(bloklar) == 0) {
        div(class = "ai-metn", cd$xulase %||% "Cavab yoxdur.")
      } else {
        tagList(lapply(seq_along(bloklar), function(i) {
          ai_blok_ui(bloklar[[i]], i)
        }))
      }
    )
  })

  # ---- sessiya bitdikdə ----
  session$onSessionEnded(function() {
    cn <- .bag$db
    if (!is.null(cn) && DBI::dbIsValid(cn)) try(DBI::dbDisconnect(cn), silent = TRUE)
  })
}

shinyApp(ui, server)
