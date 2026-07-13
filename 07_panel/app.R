# ==============================================================================
# ZARAT — VAHİD NƏZARƏT PANELİ  (Faza 3)
# ==============================================================================
# İşə salma:
#   cd ~/Desktop/Zarat_Faza2_Zavod
#   R -e "shiny::runApp('07_panel/app.R', port=3838, launch.browser=TRUE)"
#
# Tələb olunan paketlər:
#   install.packages(c("shiny","bslib","DBI","RPostgres","httr2","jsonlite",
#                      "DT","plotly","dplyr","lubridate","glue","curl"))
# ==============================================================================

# macOS fork təhlükəsizliyi — kitabxanalardan ƏVVƏL qurulmalıdır
Sys.setenv(OBJC_DISABLE_INITIALIZE_FORK_SAFETY = "YES")

library(shiny)
library(bslib)
library(DBI)
library(RPostgres)
library(httr2)
library(jsonlite)
library(DT)
library(plotly)
library(dplyr)
library(lubridate)
library(glue)

options(shiny.sanitize.errors = FALSE)
Sys.setlocale("LC_ALL", "en_US.UTF-8")

# Bütün modulları yüklə — əlifba sırası ilə:
#   baza.R → konfiq.R → mod_*.R → stil.R → yardimci.R
# Hər modul öz funksiyasını qlobal mühitə əlavə edir.
for (f in list.files(
  file.path(dirname(normalizePath(sys.frame(1)$ofile)), "R"),
  pattern    = "\\.R$",
  full.names = TRUE
)) {
  source(f, local = FALSE)
}


# ==============================================================================
# UI
# ==============================================================================

ui <- page_navbar(
  title = paste("ZARAT · SİYƏZƏN", PANEL_VERSIYA),
  theme = bs_theme(
    version      = 5,
    base_font    = font_google("Inter"),
    heading_font = font_google("Oswald"),
    primary      = "#0d9488",
    "body-bg"    = "#f6f4ef"
  ),
  header = tagList(
    tags$head(
      tags$style(HTML(STIL)),
      tags$link(rel = "stylesheet",
                href = "https://fonts.googleapis.com/css2?family=Oswald:wght@400;500;600;700&display=swap")
    ),
    # STATİK zolaq — server render olmasa da görünür
    div(style = paste("background:#0d9488; color:#fff; padding:6px 26px;",
                      "font-family:ui-monospace,Menlo,monospace; font-size:12px;"),
        paste0("PANEL ", PANEL_VERSIYA, " · yükləndi ", format(Sys.time(), "%H:%M:%S"))),
    uiOutput("proba"),
    uiOutput("basliq")
  ),

  # -------------------------------------------------- PANEL (boru xətti) -----
  nav_panel("Panel",
    mod_sensorlar_panel_UI("sensorlar")),

  # ----------------------------------------------------------- CİHAZLAR ------
  nav_panel("Cihazlar",
    mod_sensorlar_cihazlar_UI("sensorlar")),

  # ------------------------------------------------------ XƏBƏRDARLIQLAR -----
  nav_panel("Xəbərdarlıqlar",
    mod_sensorlar_alertler_UI("sensorlar")),

  # ------------------------------------------------- MƏRKƏZİ GÖNDƏRMƏ -------
  nav_panel("Mərkəzə göndərmə",
    mod_sensorlar_sync_UI("sensorlar")),

  # ---------------------------------------------------- SƏNƏDLƏR  (Faza 3) ---
  nav_panel("Sənədlər",
    mod_senedler_UI("senedler")),

  # ------------------------------------------------ AI TƏKLİFLƏR  (Faza 3) ---
  nav_panel("AI Təklifləri",
    mod_ai_teklifler_UI("teklifler")),

  # --------------------------------------------------------- ANBAR  (Faza 3) -
  nav_panel("Anbar",
    mod_anbar_UI("anbar")),

  # ------------------------------------------------------- İSTEHSAL (Faza 3) -
  nav_panel("İstehsal",
    mod_istehsal_UI("istehsal")),

  # ------------------------------------------------------ ANALİTİKA (Faza 3) -
  nav_panel("Analitika",
    mod_analitika_UI("analitika")),

  # ------------------------------------------------------- AI KÖMƏKÇİ --------
  nav_panel("AI Köməkçi",
    mod_ai_kohekci_UI("ai_k")),

  # -------------------------------------------------------- İDARƏETMƏ ---------
  nav_panel("İdarəetmə",
    mod_idareetme_UI("idareetme")),

  nav_spacer(),
  nav_item(uiOutput("saat_gostericisi"))
)


# ==============================================================================
# SERVER
# ==============================================================================

server <- function(input, output, session) {

  jurnal("=========================================")
  jurnal("SERVER BAŞLADI — ", PANEL_VERSIYA)

  # PROBA: heç nədən asılı deyil. Görünürsə, render mexanizmi işləyir.
  output$proba <- renderUI({
    jurnal("proba render olundu")
    div(style = "background:#5bd08a; color:#0e1620; padding:6px 26px; font-size:12px; font-family:ui-monospace,monospace;",
        paste("SERVER RENDER İŞLƏYİR ·", format(Sys.time(), "%H:%M:%S")))
  })

  taymer <- reactiveTimer(KFG$yenilenme_ms)

  # Ürək döyüntüsü — sessiya sağdırmı?
  dovr_sayi <- reactiveVal(0)
  observe({
    taymer()
    dovr_sayi(isolate(dovr_sayi()) + 1)
    jurnal("♥ dövr ", isolate(dovr_sayi()))
  })

  # Növbə tarixçəsi (sync qrafiki üçün)
  novbe_tarixce <- reactiveVal(
    data.frame(vaxt = as.POSIXct(character()), gozleyen = integer())
  )

  # ---- Paylaşılan reaktivlər ----
  veziyyet <- reactive({
    taymer()
    mtr <- tryCatch(api_metrikalar(), error = function(e) NULL)
    list(
      sensorlar = tehlukesiz("sensorlar", sensorlar_yigi),
      broker    = tehlukesiz("broker",    function() broker_yigi(mtr)),
      api       = tehlukesiz("api",       function() api_yigi(mtr)),
      edge      = tehlukesiz("edge",      edge_yigi),
      sync      = tehlukesiz("sync",      sync_yigi),
      merkez    = tehlukesiz("merkez",    merkez_yigi)
    )
  })

  problemler <- reactive({
    tryCatch(diaqnoz(veziyyet()), error = function(e) {
      message("[DİAQNOSTİKA XƏTASI] ", conditionMessage(e))
      list(list(kod = "PANEL_XETASI", seviyye = "kritik",
                basliq  = "Panelin daxilində xəta",
                ne_olub = conditionMessage(e),
                niye    = "Bu, zavodun problemi deyil — panelin kodundadır.",
                hell    = c("Sistemin özü işləməyə davam edir.",
                            "Bu mətni mühəndisə göndərin."),
                emr     = NULL))
    })
  })

  saglamliq <- reactive({
    st  <- veziyyet()
    cek <- c(sensorlar = 20, broker = 15, api = 20, edge = 25, sync = 10, merkez = 10)
    bal <- sapply(names(cek), function(m) {
      v <- st[[m]]$veziyyet %||% "bilinmir"
      switch(v, ok = 1, xeberdarliq = 0.5, kritik = 0, bilinmir = 0.3, 0.3)
    })
    round(sum(bal * cek))
  })

  # Növbə dərinliyi tarixçəsi
  # !!! isolate() MÜTLƏQDİR — olmasa sonsuz dövr yaranır !!!
  observe({
    tryCatch({
      st <- veziyyet()
      if (is.null(st$sync$stat)) return()
      t    <- isolate(novbe_tarixce())
      yeni <- rbind(t, data.frame(vaxt     = Sys.time(),
                                  gozleyen = as.numeric(st$sync$stat$gozleyen[1])))
      if (nrow(yeni) > 720) yeni <- tail(yeni, 720)
      novbe_tarixce(yeni)
    }, error = function(e) jurnal("[NÖVBƏ TARİXÇƏSİ] ", conditionMessage(e)))
  })

  # ---- Başlıq (health xalı) ----
  output$basliq <- renderUI({
    qoru("basliq", {
      x    <- saglamliq()
      reng <- if (x >= 90) "#5bd08a" else if (x >= 60) "#f5a524" else "#e5695f"
      hal  <- if (x >= 90) "Sistem sağlamdır"
              else if (x >= 60) "Diqqət tələb edir"
              else "Müdaxilə lazımdır"

      div(class = "zavod-bas",
          div(
            h1("Siyəzən yem zavodu — nəzarət paneli"),
            div(class = "alt",
                glue("{KFG$zavod_kod} · edge:{KFG$edge$port} → merkez:{KFG$merkez$port}"))
          ),
          div(class = "xal-qutu",
              div(class = "xal", style = glue("color:{reng};"), glue("{x}%")),
              div(class = "xal-etiket", hal))
      )
    })
  })

  output$saat_gostericisi <- renderUI({
    taymer()
    div(style = "font-family:ui-monospace,monospace; font-size:12px; color:#7a8a99; padding-top:9px;",
        format(Sys.time(), "%H:%M:%S"))
  })

  # ---- Modul server funksiyaları ----
  mod_sensorlar_Server("sensorlar",
                        veziyyet      = veziyyet,
                        problemler    = problemler,
                        saglamliq     = saglamliq,
                        novbe_tarixce = novbe_tarixce,
                        taymer        = taymer)

  mod_ai_kohekci_Server("ai_k",
                         veziyyet   = veziyyet,
                         problemler = problemler)

  mod_idareetme_Server("idareetme")

  mod_senedler_Server("senedler",      taymer = taymer)
  mod_ai_teklifler_Server("teklifler", taymer = taymer)
  mod_anbar_Server("anbar",            taymer = taymer)
  mod_istehsal_Server("istehsal",      taymer = taymer)
  mod_analitika_Server("analitika",    taymer = taymer)

  # Sessiya bitdikdə bağlantıları bağla
  session$onSessionEnded(function() {
    jurnal("!!! SESSİYA BİTDİ")
    for (h in c("edge", "merkez")) {
      cn <- .bag[[h]]
      if (!is.null(cn) && DBI::dbIsValid(cn))
        try(DBI::dbDisconnect(cn), silent = TRUE)
    }
  })
}


# ==============================================================================
# İŞƏ SALMA
# ==============================================================================

if (!nzchar(Sys.getenv("ZARAT_DIAQNOSTIKA"))) {
  shinyApp(ui, server)
} else {
  message("DİAQNOSTİKA REJİMİ — panel açılmadı. Yığıcıları əl ilə çağırın.")
}
