# ==============================================================================
# İDARƏETMƏ MODULU — xidmət idarəetməsi, loglar, bağlantı məlumatı
# ==============================================================================

xidmet_emr <- function(emr, gozle = TRUE) {
  # DİQQƏT: shQuote(tam) İŞLƏMİR — dırnaqlar sətrin içinə düşür.
  # system2 arqumentləri birbaşa ötürür, shell-dən keçmir.
  tam <- paste0(
    'export PATH="/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:$PATH"; ',
    'cd ', shQuote(LAYIHE_KOK), ' && mkdir -p _LOG && ', emr
  )

  jurnal("[ƏMR] ", substr(emr, 1, 120))

  if (!gozle) {
    tryCatch(
      system2("bash", c("-lc", tam), stdout = FALSE, stderr = FALSE, wait = FALSE),
      error = function(e) jurnal("[XƏTA] ", conditionMessage(e))
    )
    return("Fonda işə salındı — nəticəni loglardan izləyin.")
  }

  netice <- tryCatch(
    suppressWarnings(system2("bash", c("-lc", tam),
                             stdout = TRUE, stderr = TRUE, timeout = 15)),
    error = function(e) paste("XƏTA:", conditionMessage(e))
  )

  cixis  <- paste(netice, collapse = "\n")
  status <- attr(netice, "status")
  if (!is.null(status) && status != 0)
    cixis <- paste0(cixis, "\n[çıxış kodu: ", status, "]")

  jurnal("[NƏTİCƏ] ", if (nzchar(cixis)) substr(cixis, 1, 200) else "(çıxış yoxdur)")
  if (nzchar(cixis)) cixis else "(çıxış yoxdur — əmr uğurla getdi)"
}

XIDMETLER <- list(
  broker_bas = list(
    ad  = "Broker başlat",
    emr = paste(
      "if lsof -i :1883 | grep -q LISTEN; then echo 'broker artıq işləyir';",
      "else brew services start mosquitto 2>/dev/null;",
      "  sleep 2;",
      "  if ! lsof -i :1883 | grep -q LISTEN; then",
      "    nohup /usr/local/sbin/mosquitto -p 1883 >> _LOG/mosquitto.log 2>&1 &",
      "    sleep 2; echo 'birbaşa işə salındı';",
      "  else echo 'brew ilə qalxdı'; fi;",
      "fi"
    )
  ),
  broker_dayan = list(
    ad  = "Broker dayandır",
    emr = "brew services stop mosquitto"
  ),
  api_bas = list(
    ad  = "Emal proqramını başlat",
    emr = paste("source 00_env/bin/activate &&",
                "nohup uvicorn api.main:app --app-dir 03_src --port 8000",
                ">> _LOG/api.log 2>&1 & echo başladı")
  ),
  api_dayan = list(
    ad  = "Emal proqramını dayandır",
    emr = "pkill -f 'uvicorn api.main' ; echo dayandı"
  ),
  sensor_bas = list(
    ad  = "Sensorları başlat",
    emr = paste("source 00_env/bin/activate &&",
                "nohup python 03_src/publisher/sensor_simulyator.py",
                ">> _LOG/simulyator.log 2>&1 & echo başladı")
  ),
  sensor_dayan = list(
    ad  = "Sensorları dayandır",
    emr = "pkill -f sensor_simulyator ; echo dayandı"
  ),
  sync_bas = list(
    ad  = "Mərkəzə göndərməni başlat",
    emr = paste("source 00_env/bin/activate &&",
                "nohup python 03_src/sync/main.py",
                ">> _LOG/sync.log 2>&1 & echo başladı")
  ),
  sync_dayan = list(
    ad  = "Mərkəzə göndərməni dayandır",
    emr = "pkill -f 'sync/main.py' ; echo dayandı"
  ),
  ai_server_bas = list(
    ad  = "AI agent serverini başlat",
    emr = paste("source 00_env/bin/activate &&",
                "nohup uvicorn ai.agent_server:app --app-dir 03_src --port 8100",
                ">> _LOG/ai_server.log 2>&1 & echo başladı")
  ),
  ai_server_dayan = list(
    ad  = "AI agent serverini dayandır",
    emr = "pkill -f 'ai.agent_server' ; echo dayandı"
  )
)

# ------------------------------------------------------------------------------
# UI
# ------------------------------------------------------------------------------

mod_idareetme_UI <- function(id) {
  ns <- NS(id)
  layout_columns(
    col_widths = c(5, 7),
    card(
      card_header("Xidmətlər"),
      p(class = "text-muted", style = "font-size:13.5px;",
        "Sıra vacibdir: broker → emal proqramı → sensorlar → göndərici."),
      actionButton(ns("hamisi_bas"), "① Hər şeyi başlat",
                   class = "btn-success btn-idare", icon = icon("play")),
      hr(),
      actionButton(ns("broker_bas"),     "Broker başlat",
                   class = "btn-outline-success btn-idare"),
      actionButton(ns("api_bas"),        "Emal proqramını başlat",
                   class = "btn-outline-success btn-idare"),
      actionButton(ns("sensor_bas"),     "Sensorları başlat",
                   class = "btn-outline-success btn-idare"),
      actionButton(ns("sync_bas"),       "Mərkəzə göndərməni başlat",
                   class = "btn-outline-success btn-idare"),
      actionButton(ns("ai_server_bas"), "AI agent serverini başlat",
                   class = "btn-outline-success btn-idare"),
      hr(),
      actionButton(ns("hamisi_dayan"), "Səliqəli söndür",
                   class = "btn-outline-danger btn-idare", icon = icon("stop")),
      hr(),
      h6("Son əmrin nəticəsi"),
      uiOutput(ns("emr_neticesi")),
      hr(),
      h6("Bağlantı"),
      tags$div(
        style = "font-family:ui-monospace,monospace; font-size:12px; color:#5a6b7c; line-height:1.8;",
        uiOutput(ns("baglanti_melumat"))
      )
    ),
    card(
      card_header("Loglar"),
      selectInput(ns("log_fayl"), NULL,
                  choices = c("Emal proqramı"     = "_LOG/api.log",
                              "Sensorlar"          = "_LOG/simulyator.log",
                              "Mərkəzə göndərmə"  = "_LOG/sync.log",
                              "AI agent server"   = "_LOG/ai_server.log",
                              "Panel"              = "_LOG/panel.log")),
      actionButton(ns("log_yenile"), "Yenilə", class = "btn-sm btn-outline-secondary"),
      br(), br(),
      uiOutput(ns("log_metn"))
    )
  )
}

# ------------------------------------------------------------------------------
# SERVER
# ------------------------------------------------------------------------------

mod_idareetme_Server <- function(id) {
  moduleServer(id, function(input, output, session) {

    emr_cixisi <- reactiveVal("")
    log_tetik  <- reactiveVal(0)

    xidmet_isle <- function(acar, gozle = TRUE) {
      x      <- XIDMETLER[[acar]]
      netice <- xidmet_emr(x$emr, gozle = gozle)
      emr_cixisi(paste0("$ ", x$emr, "\n\n", netice))
      showNotification(glue("{x$ad} — icra olundu"), type = "message", duration = 4)
      log_tetik(isolate(log_tetik()) + 1)
      invisible(netice)
    }

    output$emr_neticesi <- renderUI({
      c <- emr_cixisi()
      tags$pre(class = "log-qutu", style = "max-height:180px; margin:0;",
               if (!nzchar(c)) "Hələ əmr işlədilməyib." else c)
    })

    observeEvent(input$broker_bas,     xidmet_isle("broker_bas",     gozle = TRUE))
    observeEvent(input$api_bas,        xidmet_isle("api_bas",        gozle = FALSE))
    observeEvent(input$sensor_bas,     xidmet_isle("sensor_bas",     gozle = FALSE))
    observeEvent(input$sync_bas,       xidmet_isle("sync_bas",       gozle = FALSE))
    observeEvent(input$ai_server_bas,  xidmet_isle("ai_server_bas",  gozle = FALSE))

    observeEvent(input$hamisi_bas, {
      skript <- paste(
        "(",
        "  echo '=== BAŞLATMA ===' ;",
        "  if lsof -i :1883 | grep -q LISTEN; then echo 'broker onsuz da işləyir' ;",
        "  else brew services start mosquitto 2>/dev/null ; sleep 2 ;",
        "    lsof -i :1883 | grep -q LISTEN || nohup /usr/local/sbin/mosquitto -p 1883 >> _LOG/mosquitto.log 2>&1 & ",
        "  fi ;",
        "  sleep 3 ;",
        "  source 00_env/bin/activate ;",
        "  nohup uvicorn api.main:app --app-dir 03_src --port 8000 >> _LOG/api.log 2>&1 &",
        "  sleep 5 ;",
        "  nohup python 03_src/publisher/sensor_simulyator.py >> _LOG/simulyator.log 2>&1 &",
        "  sleep 2 ;",
        "  nohup python 03_src/sync/main.py >> _LOG/sync.log 2>&1 &",
        "  sleep 2 ;",
        "  nohup uvicorn ai.agent_server:app --app-dir 03_src --port 8100 >> _LOG/ai_server.log 2>&1 &",
        "  echo '=== BİTDİ ===' ;",
        ") >> _LOG/baslatma.log 2>&1"
      )

      xidmet_emr(skript, gozle = FALSE)
      emr_cixisi(paste(
        "Başlatma FONDA işə düşdü — panel donmur.",
        "",
        "Sıra: broker → 3san → emal proqramı → 5san → sensorlar → 2san → göndərici → 2san → AI server",
        "",
        "Boru xəttinə baxın — soldan sağa yaşıllaşacaq.",
        "Təfərrüat: _LOG/baslatma.log",
        sep = "\n"
      ))
      showNotification("Sistem fonda qalxır — 20 saniyə gözləyin.",
                       type = "message", duration = 10)
      log_tetik(isolate(log_tetik()) + 1)
    })

    observeEvent(input$hamisi_dayan, {
      showModal(modalDialog(
        title = "Sistemi söndürmək?",
        "Sensorlar, emal proqramı, göndərici və AI server dayanacaq.",
        br(), br(),
        strong("Növbədə gözləyən məlumat itməyəcək — sistem qalxanda göndəriləcək."),
        footer = tagList(
          modalButton("İmtina"),
          actionButton(session$ns("dayan_tesdiq"), "Bəli, söndür", class = "btn-danger")
        )
      ))
    })

    observeEvent(input$dayan_tesdiq, {
      removeModal()
      skript <- paste(
        "( pkill -f sensor_simulyator ; sleep 1 ;",
        "  pkill -f 'sync/main.py' ; sleep 1 ;",
        "  pkill -f 'uvicorn api.main' ; sleep 1 ;",
        "  pkill -f 'ai.agent_server' ;",
        "  echo 'söndürüldü' ) >> _LOG/baslatma.log 2>&1"
      )
      xidmet_emr(skript, gozle = FALSE)
      emr_cixisi("Söndürmə fonda: sensorlar → göndərici → emal proqramı → AI server.\nBroker və bazalar işləməyə davam edir.")
      showNotification("Sistem səliqəli söndürülür.", type = "message")
      log_tetik(isolate(log_tetik()) + 1)
    })

    output$baglanti_melumat <- renderUI({
      tagList(
        div(glue("Zavod bazası:   {KFG$edge$host}:{KFG$edge$port}/{KFG$edge$baza}")),
        div(glue("Mərkəzi baza:   {KFG$merkez$host}:{KFG$merkez$port}/{KFG$merkez$baza}")),
        div(glue("Emal proqramı:  {KFG$api_url}")),
        div(glue("AI agent server: {KFG$ai_url}")),
        div(glue("Məlumat qutusu: {KFG$mqtt_host}:{KFG$mqtt_port}")),
        div(glue("MinIO edge:     {KFG$minio_edge_url}")),
        div(glue("MinIO mərkəz:   {KFG$minio_merkez_url}")),
        div(glue("Layihə:         {LAYIHE_KOK}"))
      )
    })

    output$log_metn <- renderUI({
      log_tetik()
      input$log_yenile

      yol   <- file.path(LAYIHE_KOK, input$log_fayl %||% "_LOG/api.log")
      metn  <- if (!file.exists(yol)) {
        paste0("Log faylı hələ yaranmayıb:\n", input$log_fayl,
               "\n\nBu, xəta deyil — həmin proqram hələ işə salınmayıb.")
      } else {
        setirler <- tryCatch(readLines(yol, warn = FALSE), error = function(e) character(0))
        if (length(setirler) == 0) paste0("Fayl boşdur: ", input$log_fayl)
        else paste(rev(tail(setirler, 80)), collapse = "\n")
      }

      tags$pre(class = "log-qutu", style = "margin:0;", metn)
    })

  })
}
