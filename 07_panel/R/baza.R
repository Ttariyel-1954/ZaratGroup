# ==============================================================================
# BAZA QATI — heç vaxt çökmür, yalnız NULL qaytarır
# Prinsip: baza sönülü olsa, panel ÇÖKMƏMƏLİDİR.
# ==============================================================================

VEZ_RENG <- c(ok = "#5bd08a", xeberdarliq = "#f5a524",
              kritik = "#e5695f", bilinmir = "#64748b")

.bag <- new.env(parent = emptyenv())
.bag$edge   <- NULL
.bag$merkez <- NULL
.bag$son_xeta     <- list(edge = NA_character_, merkez = NA_character_)
.bag$novbeti_cehd <- list(edge = 0, merkez = 0)

# Mərkəz əlçatmaz olanda 30 saniyə cəhd etmirik.
# Ölü hosta hər 5 saniyədə qoşulmaq — R-i bloklayır, panel ölür.
BACKOFF_SAN <- 30

baglanti_al <- function(hansi = c("edge", "merkez")) {
  hansi <- match.arg(hansi)
  movcud <- .bag[[hansi]]

  if (!is.null(movcud) && DBI::dbIsValid(movcud)) return(movcud)

  indi <- as.numeric(Sys.time())
  if (indi < .bag$novbeti_cehd[[hansi]]) return(NULL)

  p <- KFG[[hansi]]
  yeni <- tryCatch({
    arqler <- list(
      drv = RPostgres::Postgres(),
      host = p$host, port = p$port,
      dbname = p$baza, user = p$user,
      connect_timeout = 2,
      # bigint = "numeric" MÜTLƏQDİR.
      # Standart "integer64" count(*) nəticəsini xüsusi obyekt kimi qaytarır —
      # o isə rbind, format və plotly ilə səssizcə sınır.
      bigint = "numeric"
    )
    if (nzchar(p$parol)) arqler$password <- p$parol
    do.call(DBI::dbConnect, arqler)
  }, error = function(e) {
    .bag$son_xeta[[hansi]] <- conditionMessage(e)
    NULL
  })

  if (is.null(yeni)) {
    .bag$novbeti_cehd[[hansi]] <- indi + BACKOFF_SAN
    jurnal("[QOŞULMA] ", hansi, " əlçatmaz — ", BACKOFF_SAN, " san. cəhd etməyəcəyəm")
  } else {
    .bag$son_xeta[[hansi]] <- NA_character_
    .bag$novbeti_cehd[[hansi]] <- 0
  }

  .bag[[hansi]] <- yeni
  yeni
}

sorgu <- function(hansi, sql, params = NULL) {
  conn <- baglanti_al(hansi)
  if (is.null(conn)) return(NULL)

  tryCatch({
    if (is.null(params)) DBI::dbGetQuery(conn, sql)
    else                 DBI::dbGetQuery(conn, sql, params = params)
  }, error = function(e) {
    .bag$son_xeta[[hansi]] <- conditionMessage(e)
    try(DBI::dbDisconnect(conn), silent = TRUE)
    .bag[[hansi]] <- NULL
    NULL
  })
}

icra <- function(hansi, sql, params = NULL) {
  conn <- baglanti_al(hansi)
  if (is.null(conn)) return(FALSE)
  tryCatch({
    if (is.null(params)) DBI::dbExecute(conn, sql)
    else                 DBI::dbExecute(conn, sql, params = params)
    TRUE
  }, error = function(e) {
    .bag$son_xeta[[hansi]] <- conditionMessage(e)
    FALSE
  })
}

# --- Port yoxlaması (çəngəllənmə yoxdur) ---
port_aciq <- function(host, port, saniye = 1) {
  con <- tryCatch(
    suppressWarnings(socketConnection(
      host = host, port = port, blocking = TRUE,
      open = "r+", timeout = saniye
    )),
    error   = function(e) NULL,
    warning = function(w) NULL
  )
  if (is.null(con)) return(FALSE)
  try(close(con), silent = TRUE)
  TRUE
}

# --- Proses yoxlaması (nəticə keşlənir: 20 san.) ---
.proses <- new.env(parent = emptyenv())
.proses$kes  <- list()
.proses$vaxt <- 0
PROSES_KES_SAN <- 20

proses_var <- function(numune) {
  indi <- as.numeric(Sys.time())

  if (indi - .proses$vaxt > PROSES_KES_SAN) {
    siyahi <- tryCatch(
      suppressWarnings(system2("pgrep", "-fl .", stdout = TRUE, stderr = FALSE)),
      error = function(e) character(0)
    )
    .proses$kes  <- if (length(siyahi)) siyahi else character(0)
    .proses$vaxt <- indi
  }

  any(grepl(numune, .proses$kes, fixed = TRUE))
}

# --- FastAPI metrikalar ---
api_metrikalar <- function() {
  tryCatch({
    httr2::request(paste0(KFG$api_url, "/metrikalar")) |>
      httr2::req_timeout(3) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
  }, error = function(e) NULL)
}

# --- AI agent xidmətinə sorğu ---
ai_agent_cagiris <- function(endpoint, data = NULL, timeout = 60) {
  tryCatch({
    r <- httr2::request(paste0(KFG$ai_url, endpoint))
    if (!is.null(data))
      r <- r |> httr2::req_body_json(data)
    r |>
      httr2::req_timeout(timeout) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
  }, error = function(e) {
    list(ugurlu = FALSE, xeta = conditionMessage(e))
  })
}
