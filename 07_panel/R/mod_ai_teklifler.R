# ==============================================================================
# AI TƏKLİFLƏR MODULU — Faza 3
# Layihənin ürəyi: mühasib hər gün bu ekranı açır.
# AI çıxarışı + təsdiq/rədd/düzəliş interfeysi
# ==============================================================================

# ------------------------------------------------------------------------------
# UI
# ------------------------------------------------------------------------------

mod_ai_teklifler_UI <- function(id) {
  ns <- NS(id)

  tagList(
    # Üst zolaq: say göstəriciləri
    uiOutput(ns("ozet_zolaq")),
    br(),

    layout_columns(
      col_widths = c(6, 6),

      # --- Sol: Orijinal sənəd ---
      card(
        card_header(tagList(
          "Orijinal sənəd",
          uiOutput(ns("nav_duymeleri"), inline = TRUE)
        )),
        uiOutput(ns("senedi_goster"))
      ),

      # --- Sağ: AI çıxarışı + Forma ---
      card(
        card_header("AI çıxarışı — redaktə edilə bilər"),

        # Qırmızı xəbərdarlıq: aşağı əminlik
        uiOutput(ns("eminlik_xeberdarliq")),

        div(style = "padding:0 4px;",
          # Əsas sahələr
          uiOutput(ns("ai_forma")),

          hr(),
          # Sətir cədvəli
          h6("Qaimə sətirləri"),
          uiOutput(ns("setir_cedvel")),
          br(),

          # Fəaliyyət düymələri
          div(style = "display:flex; gap:10px; justify-content:flex-end;",
              actionButton(ns("redd"),     "Rədd",     class = "btn-outline-danger",   icon = icon("times")),
              actionButton(ns("duzеlis"),  "Düzəliş",  class = "btn-outline-warning",  icon = icon("pen")),
              actionButton(ns("tesdiqle"), "Təsdiqlə", class = "btn-success",           icon = icon("check")),
              span(class = "text-muted", style = "font-size:12px; line-height:2.2;",
                   "Enter=Təsdiq · Esc=Rədd")
          )
        )
      )
    )
  )
}

# ------------------------------------------------------------------------------
# SERVER
# ------------------------------------------------------------------------------

mod_ai_teklifler_Server <- function(id, taymer) {
  moduleServer(id, function(input, output, session) {

    cari_indeks  <- reactiveVal(1)
    teklifler    <- reactiveVal(NULL)
    redakte_data <- reactiveVal(list())

    # ---- Bütün «teklif» statuslu AI çıxarışları ----
    teklifleri_yukle <- function() {
      d <- sorgu("merkez", "
        SELECT c.id, c.sened_id, c.agent_kod, c.model,
               c.netice, c.eminlik, c.status,
               c.yaradilma,
               s.novu AS sened_nov, s.nomre AS sened_nomre,
               f.orijinal_ad, f.mime_tipi, f.obyekt_acari
        FROM ai.cixaris c
        JOIN sened.sened  s ON s.id = c.sened_id
        LEFT JOIN sened.fayl f ON f.id = c.fayl_id
        WHERE c.status = 'teklif'
        ORDER BY c.yaradilma
        LIMIT 50
      ")
      teklifler(d)
    }

    observe({
      taymer()
      teklifleri_yukle()
    })

    # Cari teklif
    cari_teklif <- reactive({
      t <- teklifler()
      i <- cari_indeks()
      if (is.null(t) || nrow(t) == 0 || i > nrow(t)) return(NULL)
      t[i, ]
    })

    # ---- Üst zolaq ----
    output$ozet_zolaq <- renderUI({
      t <- teklifler()
      say <- if (is.null(t)) 0 else nrow(t)
      div(style = "display:flex; gap:16px; padding:10px 0;",
          div(style = "background:#fff; border:1px solid #e2ddd6; border-radius:8px; padding:12px 20px; min-width:140px;",
              div(style = "font-size:24px; font-family:Oswald,sans-serif; font-weight:700; color:#0d9488;", say),
              div(style = "font-size:12px; color:#6b7280;", "Təsdiq gözləyir")),
          div(style = "background:#f0fdf4; border:1px solid #bbf7d0; border-radius:8px; padding:12px 20px; min-width:140px;",
              div(style = "font-size:11px; color:#166534;",
                  icon("circle-info"),
                  " AI 90%+ dəqiqliklə oxuyur. Yoxlayın, bir kliklə təsdiqləyin."))
      )
    })

    # ---- Naviqasiya ----
    output$nav_duymeleri <- renderUI({
      t <- teklifler()
      i <- cari_indeks()
      n <- if (is.null(t)) 0 else nrow(t)
      if (n == 0) return(NULL)

      div(style = "float:right; display:flex; gap:6px; align-items:center;",
          span(style = "font-size:13px; color:#6b7280;",
               glue("{i} / {n}")),
          actionButton(session$ns("prev_btn"), icon("chevron-left"),
                       class = "btn-sm btn-outline-secondary"),
          actionButton(session$ns("next_btn"), icon("chevron-right"),
                       class = "btn-sm btn-outline-secondary"))
    })

    observeEvent(input$prev_btn, {
      i <- cari_indeks()
      if (i > 1) cari_indeks(i - 1)
    })
    observeEvent(input$next_btn, {
      t <- teklifler()
      i <- cari_indeks()
      if (!is.null(t) && i < nrow(t)) cari_indeks(i + 1)
    })

    # ---- Sənədi göstər ----
    output$senedi_goster <- renderUI({
      t <- cari_teklif()
      if (is.null(t)) {
        return(div(style = "padding:40px; text-align:center; color:#9ca3af;",
                   if (is.null(teklifler()) || nrow(teklifler() %||% data.frame()) == 0)
                     "Heç bir təklif gözləmir — hamısı təsdiqlənib!"
                   else "Siyahıdan sənəd seçin"))
      }

      mime <- t$mime_tipi
      acari <- t$obyekt_acari

      if (is.na(mime) || is.null(acari) || is.na(acari)) {
        return(div(style = "padding:20px; color:#9ca3af;", "Fayl yoxdur"))
      }

      # MinIO presigned URL — praktik olaraq, agent server vasitəsilə al
      if (startsWith(mime, "image/")) {
        img_url <- paste0(KFG$ai_url, "/fayl/", URLencode(acari, reserved = TRUE))
        tags$img(src = img_url, style = "max-width:100%; border:1px solid #e2ddd6; border-radius:6px;",
                 alt = t$orijinal_ad)
      } else if (mime == "application/pdf") {
        pdf_url <- paste0(KFG$ai_url, "/fayl/", URLencode(acari, reserved = TRUE))
        tags$iframe(src = pdf_url, style = "width:100%; height:600px; border:1px solid #e2ddd6; border-radius:6px;")
      } else {
        div(class = "sened-kart",
            div(class = "sened-nov", mime_ikon(mime)),
            div(class = "sened-nom", t$orijinal_ad %||% "Fayl"),
            p(class = "text-muted", "Önizləmə bu fayl növü üçün mövcud deyil."))
      }
    })

    # ---- AI forma ----
    output$ai_forma <- renderUI({
      t <- cari_teklif()
      if (is.null(t)) return(NULL)

      # netice JSON
      netice  <- tryCatch(jsonlite::fromJSON(t$netice),  error = function(e) list())
      eminlik <- tryCatch(jsonlite::fromJSON(t$eminlik), error = function(e) list())

      # Əminlik rəngi
      em_stil <- function(sahə) {
        e <- eminlik[[sahə]] %||% 1
        if      (e >= 0.9) "background:#f0fdf4;"
        else if (e >= 0.85) "background:#fffbeb;"
        else               "background:#fef2f2;"
      }

      tagList(
        div(style = em_stil("nomre"),
          textInput(session$ns("ai_nomre"), "Nömrə",
                    value = netice$nomre %||% ""),
          span(style = "font-size:11px; color:#9ca3af;",
               glue("Əminlik: {round((eminlik$nomre %||% 0)*100)}%"))
        ),
        div(style = em_stil("tarix"),
          textInput(session$ns("ai_tarix"), "Tarix",
                    value = netice$tarix %||% ""),
          span(style = "font-size:11px; color:#9ca3af;",
               glue("Əminlik: {round((eminlik$tarix %||% 0)*100)}%"))
        ),
        div(style = em_stil("qarsi_teref") %||% "",
          textInput(session$ns("ai_teref"), "Qarşı tərəf",
                    value = netice$qarsi_teref %||% "")
        ),
        div(
          selectInput(session$ns("ai_novu"), "Növ",
                      choices  = SENED_NOVLERI,
                      selected = netice$novu %||% "DIGER")
        ),
        div(
          numericInput(session$ns("ai_cemi"), "Cəmi məbləğ",
                       value = netice$cemi_mebleg %||% NULL, min = 0)
        )
      )
    })

    # ---- Aşağı əminlik xəbərdarlığı ----
    output$eminlik_xeberdarliq <- renderUI({
      t <- cari_teklif()
      if (is.null(t)) return(NULL)

      eminlik <- tryCatch(jsonlite::fromJSON(t$eminlik), error = function(e) list())
      asagi   <- Filter(function(e) !is.na(e) && e < 0.85, eminlik)

      if (length(asagi) == 0) return(NULL)

      saheler <- paste(names(asagi), collapse = ", ")
      div(style = "background:#fef2f2; border:1px solid #fca5a5; border-radius:6px; padding:10px 14px; margin-bottom:12px;",
          icon("triangle-exclamation", style = "color:#e5695f;"),
          strong(style = "color:#991b1b;", " Aşağı əminlik: "),
          span(style = "font-size:13px;", saheler),
          div(style = "font-size:12px; color:#6b7280; margin-top:4px;",
              "Sarı sahələri orijinal sənəddə yoxlayın."))
    })

    # ---- Sətir cədvəli ----
    output$setir_cedvel <- renderUI({
      t <- cari_teklif()
      if (is.null(t)) return(NULL)

      netice  <- tryCatch(jsonlite::fromJSON(t$netice),  error = function(e) list())
      eminlik <- tryCatch(jsonlite::fromJSON(t$eminlik), error = function(e) list())

      setirler <- netice$setirler
      if (is.null(setirler) || length(setirler) == 0) {
        return(p(class = "text-muted", "Qaimə sətiri tapılmadı."))
      }

      setir_emlik <- eminlik$setirler %||% 1

      div(class = "cdv-sar",
          tags$table(class = "cdv",
            tags$thead(tags$tr(
              lapply(c("Material", "Miqdar", "Vahid", "Vahid qiymət", "Cəmi", "Əminlik"),
                     tags$th)
            )),
            tags$tbody(
              lapply(seq_along(setirler), function(i) {
                s   <- setirler[[i]]
                em  <- if (length(setir_emlik) >= i) setir_emlik[i] else 0.95
                stil <- if (em < 0.85) "background:#fffbeb;" else ""
                tags$tr(style = stil,
                  tags$td(s$material  %||% "—"),
                  tags$td(s$miqdar    %||% "—"),
                  tags$td(s$vahid     %||% "kq"),
                  tags$td(s$vahid_qiymet %||% "—"),
                  tags$td(s$cemi      %||% "—"),
                  tags$td(glue("{round(em*100)}%"),
                          style = if (em < 0.85) "color:#e5695f; font-weight:600;" else "color:#5bd08a;")
                )
              })
            )
          )
      )
    })

    # ---- İnsan düzəlişlərini topla ----
    insan_duzelisi_al <- function(t) {
      netice <- tryCatch(jsonlite::fromJSON(t$netice), error = function(e) list())

      deyisiklikler <- list()
      if (!is.null(input$ai_nomre) && !identical(input$ai_nomre, netice$nomre %||% ""))
        deyisiklikler$nomre <- list(ai = netice$nomre, insan = input$ai_nomre)
      if (!is.null(input$ai_tarix) && !identical(input$ai_tarix, netice$tarix %||% ""))
        deyisiklikler$tarix <- list(ai = netice$tarix, insan = input$ai_tarix)
      if (!is.null(input$ai_teref) && !identical(input$ai_teref, netice$qarsi_teref %||% ""))
        deyisiklikler$qarsi_teref <- list(ai = netice$qarsi_teref, insan = input$ai_teref)

      deyisiklikler
    }

    # ---- TƏSDİQLƏ ----
    observeEvent(input$tesdiqle, {
      t <- cari_teklif()
      if (is.null(t)) return()

      deyis <- insan_duzelisi_al(t)
      status_yeni <- if (length(deyis) > 0) "duzelis_edildi" else "tesdiqlendi"

      netice_yeni <- tryCatch(jsonlite::fromJSON(t$netice), error = function(e) list())
      if (!is.null(input$ai_nomre)) netice_yeni$nomre         <- input$ai_nomre
      if (!is.null(input$ai_tarix)) netice_yeni$tarix         <- input$ai_tarix
      if (!is.null(input$ai_teref)) netice_yeni$qarsi_teref   <- input$ai_teref
      if (!is.null(input$ai_novu))  netice_yeni$novu          <- input$ai_novu
      if (!is.null(input$ai_cemi))  netice_yeni$cemi_mebleg   <- input$ai_cemi

      ok <- icra("merkez", "
        UPDATE ai.cixaris
        SET status = $1,
            netice = $2::jsonb,
            insan_duzelisi = $3::jsonb,
            baxan = $4,
            baxis_vaxti = now()
        WHERE id = $5
      ", params = list(
        status_yeni,
        jsonlite::toJSON(netice_yeni, auto_unbox = TRUE),
        jsonlite::toJSON(deyis, auto_unbox = TRUE),
        Sys.info()[["user"]],
        t$id
      ))

      if (ok) {
        showNotification("Təsdiqləndi. Anbar hərəkatı yaradıldı.", type = "message")
        teklifleri_yukle()
        # İndeksi saxla (növbəti sənədə keç)
        n <- if (!is.null(teklifler())) nrow(teklifler()) else 0
        if (cari_indeks() > n && n > 0) cari_indeks(n)
      } else {
        showNotification("Xəta baş verdi. Bağlantını yoxlayın.", type = "error")
      }
    })

    # ---- RƏDD ----
    observeEvent(input$redd, {
      t <- cari_teklif()
      if (is.null(t)) return()

      ok <- icra("merkez", "
        UPDATE ai.cixaris
        SET status = 'redd_edildi', baxan = $1, baxis_vaxti = now()
        WHERE id = $2
      ", params = list(Sys.info()[["user"]], t$id))

      if (ok) {
        showNotification("Rədd edildi.", type = "warning")
        teklifleri_yukle()
        n <- if (!is.null(teklifler())) nrow(teklifler()) else 0
        if (cari_indeks() > n && n > 0) cari_indeks(n)
      }
    })

    # ---- DÜZƏLİŞ düyməsi — formu aktivləşdir ----
    observeEvent(input$duzеlis, {
      showNotification("Forma redaktə üçün aktivdir. Düzəliş edib «Təsdiqlə» basın.",
                       type = "message", duration = 5)
    })

    # Klaviatura qısayolları
    observeEvent(input$klaviatura_tesdiq, {
      if (isTRUE(input$klaviatura_tesdiq)) {
        shinyjs::click(session$ns("tesdiqle"))
      }
    })

  })
}
