# ==============================================================================
# AI KÖMƏKÇİ MODULU — Faza 2 söhbət funksionallığı
# AI qaydaları ƏVƏZ ETMİR — onları izah edir.
# Açar yoxdursa, panel yenə işləyir.
# ==============================================================================

ai_hazirdir <- function() nzchar(KFG$ai_acar)

ai_kontekst <- function(st, problemler) {
  jsonlite::toJSON(list(
    zaman   = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    zavod   = KFG$zavod_kod,
    boru_xetti = lapply(
      list(sensorlar = st$sensorlar, broker = st$broker, api = st$api,
           edge = st$edge, sync = st$sync, merkez = st$merkez),
      function(m) list(veziyyet = m$veziyyet,
                       reqem    = as.character(m$reqem),
                       detal    = as.character(m$detal))
    ),
    problemler = lapply(problemler, function(p)
      list(kod = p$kod, seviyye = p$seviyye, basliq = p$basliq))
  ), auto_unbox = TRUE)
}

AI_SISTEM <- paste(
  "Sən Siyəzən yem zavodunun telemetriya sisteminin köməkçisisən.",
  "Səninlə danışan adam ZAVOD OPERATORUDUR — mühəndis deyil, proqramçı deyil.",
  "",
  "Qaydalar:",
  "1. YALNIZ Azərbaycan dilində cavab ver.",
  "2. Texniki jarqon işlətmə. 'FastAPI' yerinə 'emal proqramı', 'MQTT' yerinə 'məlumat qutusu' de.",
  "3. Qısa yaz. Operator ekranda oxuyur, kitab oxumur.",
  "4. Həmişə KONKRET addım ver: 'nəyi yoxla', 'hansı düyməni bas'.",
  "5. Data itkisi barədə həmişə sakitləşdir — sistem outbox pattern istifadə edir,",
  "   şəbəkə kəsilsə də məlumat itmir, zavodda gözləyir.",
  "6. Bilmədiyini uydurma. Əmin deyilsənsə: 'mühəndisə müraciət edin' de.",
  "",
  "Sistemin quruluşu: Sensorlar → məlumat qutusu → emal proqramı → zavod bazası",
  "→ göndərici → Bakıdakı mərkəzi baza → AI analiz.",
  sep = "\n"
)

ai_sorus <- function(sual, kontekst, tarixce = list()) {
  if (!ai_hazirdir())
    return("AI açarı qurulmayıb. .env faylına ANTHROPIC_API_KEY əlavə edin.")

  mesajlar <- c(
    tarixce,
    list(list(role = "user", content = paste0(
      "SİSTEMİN HAZIRKI VƏZİYYƏTİ:\n", kontekst,
      "\n\nOPERATORUN SUALI:\n", sual
    )))
  )

  tryCatch({
    cavab <- httr2::request("https://api.anthropic.com/v1/messages") |>
      httr2::req_headers(
        "x-api-key"          = KFG$ai_acar,
        "anthropic-version"  = "2023-06-01",
        "content-type"       = "application/json"
      ) |>
      httr2::req_body_json(list(
        model      = KFG$ai_model,
        max_tokens = 1200,
        system     = AI_SISTEM,
        messages   = mesajlar
      )) |>
      httr2::req_timeout(45) |>
      httr2::req_perform() |>
      httr2::resp_body_json()

    metnler <- vapply(
      Filter(function(b) identical(b$type, "text"), cavab$content),
      function(b) b$text, character(1)
    )
    paste(metnler, collapse = "\n")
  }, error = function(e) {
    paste0("AI-a müraciət alınmadı: ", conditionMessage(e),
           "\n\nAşağıdakı hazır həll addımlarından istifadə edin.")
  })
}

# ------------------------------------------------------------------------------
# UI
# ------------------------------------------------------------------------------

mod_ai_kohekci_UI <- function(id) {
  ns <- NS(id)
  layout_columns(
    col_widths = c(4, 8),
    card(
      card_header("Tez suallar"),
      actionButton(ns("ai_veziyyet"), "Sistem necədir?",
                   class = "btn-idare btn-outline-primary"),
      actionButton(ns("ai_problem"), "Problemi izah et",
                   class = "btn-idare btn-outline-danger"),
      actionButton(ns("ai_neetmeli"), "Mən nə etməliyəm?",
                   class = "btn-idare btn-outline-warning"),
      actionButton(ns("ai_alert"), "Alertlər nə deyir?",
                   class = "btn-idare btn-outline-secondary"),
      hr(),
      textAreaInput(ns("ai_sual"), "Öz sualınız", rows = 4,
                    placeholder = "Məsələn: S004 niyə tez-tez xəbərdarlıq verir?"),
      actionButton(ns("ai_gonder"), "Soruş",
                   class = "btn-primary btn-idare", icon = icon("paper-plane")),
      br(), br(),
      uiOutput(ns("ai_status"))
    ),
    card(card_header("Söhbət"), uiOutput(ns("ai_sohbet")))
  )
}

# ------------------------------------------------------------------------------
# SERVER
# ------------------------------------------------------------------------------

mod_ai_kohekci_Server <- function(id, veziyyet, problemler) {
  moduleServer(id, function(input, output, session) {

    ai_tarixce <- reactiveVal(list())

    output$ai_status <- renderUI({
      if (ai_hazirdir())
        div(style = "font-size:12.5px; color:#2f8f5b;",
            icon("circle-check"),
            glue(" AI qoşuludur ({KFG$ai_model})"))
      else
        div(style = "font-size:12.5px; color:#b9781a;",
            icon("triangle-exclamation"),
            " AI açarı yoxdur. .env → ANTHROPIC_API_KEY. Panel açarsız da tam işləyir.")
    })

    ai_isle <- function(sual) {
      withProgress(message = "AI düşünür...", value = 0.5, {
        k     <- ai_kontekst(veziyyet(), problemler())
        cavab <- ai_sorus(sual, k, isolate(ai_tarixce()))
        t     <- isolate(ai_tarixce())
        t[[length(t) + 1]] <- list(sual = sual, cavab = cavab, vaxt = Sys.time())
        if (length(t) > 12) t <- tail(t, 12)
        ai_tarixce(t)
      })
    }

    observeEvent(input$ai_veziyyet,  ai_isle("Sistem indi necədir? Qısa xülasə ver."))
    observeEvent(input$ai_problem,   ai_isle("Hazırkı problemləri sadə dildə izah et. Ən vacibi hansıdır?"))
    observeEvent(input$ai_neetmeli,  ai_isle("Mən indi konkret nə etməliyəm? Addım-addım de."))
    observeEvent(input$ai_alert,     ai_isle("Aktiv xəbərdarlıqlar nə deməkdir? Təhlükəlidirmi?"))
    observeEvent(input$ai_gonder, {
      req(nzchar(input$ai_sual))
      ai_isle(input$ai_sual)
      updateTextAreaInput(session, "ai_sual", value = "")
    })

    output$ai_sohbet <- renderUI({
      t <- ai_tarixce()
      if (length(t) == 0) {
        return(div(style = "color:#7a8a99; padding:26px; text-align:center;",
                   p("Soldakı düymələrdən birini basın, ya da öz sualınızı yazın."),
                   p(style = "font-size:13px;",
                     "AI sistemin hazırkı vəziyyətini görür — konkret cavab verə bilər.")))
      }
      lapply(rev(t), function(x) tagList(
        div(class = "ai-sual", strong("Siz: "), x$sual),
        div(class = "ai-cavab", x$cavab),
        br()
      ))
    })

  })
}
