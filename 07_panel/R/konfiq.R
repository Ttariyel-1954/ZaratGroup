# ==============================================================================
# KONFİQURASİYA — .env-dən oxuma (həqiqətin BİR mənbəyi)
# Bütün modulların əvvəl yüklənən faylı. KFG, LAYIHE_KOK, PANEL_VERSIYA burada.
# ==============================================================================

PANEL_VERSIYA <- "v13"   # Faza 3 başlayır

LAYIHE_KOK <- Sys.getenv("ZARAT_KOK",
                          path.expand("~/Desktop/Zarat_Faza2_Zavod"))

env_oxu <- function(yol) {
  if (!file.exists(yol)) return(list())
  setirler <- readLines(yol, warn = FALSE, encoding = "UTF-8")
  setirler <- setirler[grepl("=", setirler) & !grepl("^\\s*#", setirler)]
  netice <- list()
  for (s in setirler) {
    hisse <- strsplit(s, "=", fixed = TRUE)[[1]]
    if (length(hisse) < 2) next
    ad    <- trimws(hisse[1])
    deyer <- trimws(paste(hisse[-1], collapse = "="))
    deyer <- sub("^['\"]|['\"]$", "", deyer)
    if (nzchar(ad)) netice[[ad]] <- deyer
  }
  netice
}

ENV <- env_oxu(file.path(LAYIHE_KOK, "01_config", ".env"))

kfg <- function(ad, susma = "") {
  d <- ENV[[ad]]
  if (is.null(d) || !nzchar(d)) {
    d2 <- Sys.getenv(ad, "")
    if (nzchar(d2)) return(d2)
    return(susma)
  }
  d
}

KFG <- list(
  edge = list(
    host  = kfg("EDGE_DB_HOST", "localhost"),
    port  = as.integer(kfg("EDGE_DB_PORT", "5434")),
    baza  = kfg("EDGE_DB_NAME", "zavod_edge_db"),
    user  = kfg("EDGE_DB_USER", Sys.info()[["user"]]),
    parol = kfg("EDGE_DB_PASSWORD", "")
  ),
  merkez = list(
    host  = kfg("MERKEZ_DB_HOST", "localhost"),
    port  = as.integer(kfg("MERKEZ_DB_PORT", "5432")),
    baza  = kfg("MERKEZ_DB_NAME", "zarat_erp_2"),
    user  = kfg("MERKEZ_DB_USER", Sys.info()[["user"]]),
    parol = kfg("MERKEZ_DB_PASSWORD", "")
  ),
  api_url    = kfg("API_URL",   "http://127.0.0.1:8000"),
  ai_url     = kfg("AI_URL",    "http://127.0.0.1:8100"),
  mqtt_host  = kfg("MQTT_HOST", "localhost"),
  mqtt_port  = as.integer(kfg("MQTT_PORT", "1883")),
  zavod_kod  = kfg("ZAVOD_KOD", "SIYEZEN"),

  # AI — Anthropic
  ai_acar  = kfg("ANTHROPIC_API_KEY", ""),
  ai_model = kfg("AI_MODEL", "claude-sonnet-4-6"),

  # MinIO — fayl yaddaşı
  minio_edge_url   = kfg("MINIO_EDGE_URL",   "http://localhost:9000"),
  minio_merkez_url = kfg("MINIO_MERKEZ_URL", "http://Tariyels-MacBook-Pro.local:9000"),
  minio_bucket     = kfg("MINIO_BUCKET",     "zarat-sened"),

  # Hədlər
  susma_deq        = as.numeric(kfg("SUSMA_HEDD_DEQ",   "5")),
  novbe_hedd       = as.integer(kfg("PANEL_NOVBE_HEDD", "1000")),
  gecikme_hedd_sn  = as.integer(kfg("PANEL_GECIKME_HEDD", "300")),
  yenilenme_ms     = as.integer(kfg("PANEL_YENILENME_MS", "5000")),

  # AI xərc limiti (gündəlik token)
  ai_gunluk_limit  = as.integer(kfg("AI_GUNLUK_TOKEN_LIMITI", "500000"))
)
