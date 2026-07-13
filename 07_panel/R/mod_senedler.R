# ==============================================================================
# SƏNƏDLƏR MODULU — Faza 3
# Sənəd yükləmə, siyahı, önizləmə
# ==============================================================================

SENED_NOVLERI <- c(
  "Mədaxil qaiməsi"   = "QAIME_MEDAXIL",
  "Məxaric qaiməsi"   = "QAIME_MEXARIC",
  "Təhvil aktı"       = "AKT_TEHVIL",
  "Müqavilə"          = "MUQAVILE",
  "Resept"            = "RESEPT",
  "Lab nəticəsi"      = "LAB_NETICE",
  "Əmr"               = "EMR",
  "Sertifikat"        = "SERTIFIKAT",
  "Hesab-faktura"     = "HESAB_FAKTURA",
  "Digər"             = "DIGER"
)

SENED_STATUSLARI <- c(
  "Qaralama"           = "qaralama",
  "Təsdiq gözləyir"    = "tesdiq_gozleyir",
  "Təsdiqləndi"        = "tesdiqlendi",
  "Rədd edildi"        = "redd_edildi",
  "Ləğv"               = "legv"
)

ICAZE_VERILEN_MIMELERI <- c(
  "application/pdf",
  "image/jpeg", "image/png", "image/webp",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
)

# ------------------------------------------------------------------------------
# UI
# ------------------------------------------------------------------------------

mod_senedler_UI <- function(id) {
  ns <- NS(id)

  layout_columns(
    col_widths = c(4, 8),

    # --- Sol panel: Yükləmə + Forma ---
    tagList(
      card(
        card_header("Sənəd yüklə"),
        fileInput(ns("fayl"), NULL,
                  accept   = c(".pdf", ".jpg", ".jpeg", ".png", ".xlsx", ".xls", ".docx"),
                  multiple = TRUE,
                  buttonLabel = "Fayl seç...",
                  placeholder = "PDF, şəkil, Excel, Word"),
        selectInput(ns("nov"),    "Sənəd növü", choices = SENED_NOVLERI),
        textInput(ns("nomre"),    "Sənəd nömrəsi (varsa)", placeholder = "QM-2026-441"),
        dateInput(ns("tarix"),    "Sənədin tarixi", value = Sys.Date(),
                  language = "az", format = "dd.mm.yyyy"),
        textInput(ns("teref"),    "Qarşı tərəf", placeholder = "Aqro-MMC"),
        textAreaInput(ns("qeyd"), "Qeyd", rows = 2),
        actionButton(ns("yukle"), "Yüklə və AI növbəsinə göndər",
                     class = "btn-primary btn-idare", icon = icon("upload")),
        uiOutput(ns("yukle_netice"))
      ),
      card(
        card_header("Süzgəc"),
        selectInput(ns("suzgec_nov"), "Növ",
                    choices = c("Hamısı" = "", SENED_NOVLERI)),
        selectInput(ns("suzgec_status"), "Status",
                    choices = c("Hamısı" = "", SENED_STATUSLARI)),
        dateRangeInput(ns("suzgec_tarix"), "Tarix aralığı",
                       start = Sys.Date() - 30, end = Sys.Date(),
                       language = "az", format = "dd.mm.yyyy", separator = "—"),
        actionButton(ns("axtar"), "Axtar", class = "btn-outline-primary btn-idare")
      )
    ),

    # --- Sağ panel: Siyahı + Önizləmə ---
    tagList(
      card(
        card_header(
          tagList("Sənədlər",
                  actionButton(ns("yenile"), icon("rotate"), class = "btn-sm btn-outline-secondary float-end"))
        ),
        DTOutput(ns("sened_cedvel"))
      ),
      card(
        card_header("Önizləmə"),
        uiOutput(ns("onizleme"))
      )
    )
  )
}

# ------------------------------------------------------------------------------
# SERVER
# ------------------------------------------------------------------------------

mod_senedler_Server <- function(id, taymer) {
  moduleServer(id, function(input, output, session) {

    secili_sened <- reactiveVal(NULL)
    yukle_melumat <- reactiveVal(NULL)

    # ---- Siyahı ----
    sened_data <- reactive({
      input$axtar
      input$yenile
      taymer()

      nov    <- input$suzgec_nov
      status <- input$suzgec_status
      bas    <- format(input$suzgec_tarix[1], "%Y-%m-%d")
      son    <- format(input$suzgec_tarix[2], "%Y-%m-%d")

      sql <- glue("
        SELECT s.id,
               s.novu AS \"Növ\",
               COALESCE(s.nomre, '—') AS \"Nömrə\",
               to_char(s.sened_tarixi, 'DD.MM.YYYY') AS \"Tarix\",
               COALESCE(s.qarsi_teref, '—') AS \"Qarşı tərəf\",
               s.status AS \"Status\",
               CASE WHEN s.sync_status = 0 THEN '⏳' ELSE '✓' END AS \"Mərkəz\",
               (SELECT count(*) FROM sened_fayl f WHERE f.sened_id = s.id) AS \"Fayl\",
               to_char(s.yaradilma_vaxti, 'DD.MM HH24:MI') AS \"Yaradıldı\"
        FROM sened s
        WHERE ('{ nov }' = '' OR s.novu = '{ nov }')
          AND ('{ status }' = '' OR s.status = '{ status }')
          AND (s.sened_tarixi IS NULL
               OR s.sened_tarixi BETWEEN '{ bas }'::date AND '{ son }'::date)
        ORDER BY s.id DESC
        LIMIT 200
      ")

      sorgu("edge", sql)
    })

    output$sened_cedvel <- renderDT({
      d <- sened_data()
      if (is.null(d)) d <- data.frame(Vəziyyət = "Baza əlçatmazdır")

      # ID sütununu gizlət, amma seçim üçün saxla
      goster_d <- if ("id" %in% names(d)) d[, names(d) != "id", drop = FALSE] else d

      datatable(
        goster_d,
        rownames  = FALSE,
        selection = "single",
        class     = "compact stripe hover",
        options   = list(
          pageLength = 15,
          dom        = "ftp",
          language   = list(search = "Axtar:", info = "_{start}-{end} / {total}")
        )
      ) |>
        formatStyle("Status",
                    color = styleEqual(
                      c("qaralama","tesdiq_gozleyir","tesdiqlendi","redd_edildi","legv"),
                      c("#64748b","#f5a524","#5bd08a","#e5695f","#9ca3af")
                    ))
    })

    # Seçili sənədi izlə
    observeEvent(input$sened_cedvel_rows_selected, {
      d <- sened_data()
      if (is.null(d) || length(input$sened_cedvel_rows_selected) == 0) {
        secili_sened(NULL)
        return()
      }
      indeks <- input$sened_cedvel_rows_selected
      sened_id <- d$id[indeks]
      secili_sened(sened_id)
    })

    # ---- Önizləmə ----
    output$onizleme <- renderUI({
      sid <- secili_sened()
      if (is.null(sid)) {
        return(div(style = "padding:30px; text-align:center; color:#9ca3af;",
                   "Siyahıdan sənəd seçin"))
      }

      # Faylları tap
      fayllar <- sorgu("edge", glue("
        SELECT id, orijinal_ad, mime_tipi, olcu_bayt, obyekt_acari, sha256
        FROM sened_fayl
        WHERE sened_id = {sid}
        ORDER BY id
      "))

      sened <- sorgu("edge", glue("
        SELECT id, novu, nomre, sened_tarixi, qarsi_teref, qeyd, status, metadata
        FROM sened WHERE id = {sid}
      "))

      if (is.null(sened) || nrow(sened) == 0)
        return(div("Sənəd tapılmadı"))

      s <- sened[1, ]

      tagList(
        div(style = "font-size:11px; color:#9ca3af; margin-bottom:12px;",
            glue("№{s$id} · {s$novu} · {s$status}")),
        tags$dl(class = "row",
          tags$dt(class = "col-sm-4", "Nömrə"),
          tags$dd(class = "col-sm-8", s$nomre %||% "—"),
          tags$dt(class = "col-sm-4", "Tarix"),
          tags$dd(class = "col-sm-8",
                  if (is.na(s$sened_tarixi)) "—" else format(as.Date(s$sened_tarixi), "%d.%m.%Y")),
          tags$dt(class = "col-sm-4", "Qarşı tərəf"),
          tags$dd(class = "col-sm-8", s$qarsi_teref %||% "—"),
          tags$dt(class = "col-sm-4", "Qeyd"),
          tags$dd(class = "col-sm-8", s$qeyd %||% "—")
        ),
        if (!is.null(fayllar) && nrow(fayllar) > 0) {
          tagList(
            h6(glue("{nrow(fayllar)} fayl")),
            lapply(seq_len(nrow(fayllar)), function(i) {
              f <- fayllar[i, ]
              div(class = "sened-kart",
                  div(class = "sened-nov",
                      mime_ikon(f$mime_tipi), " ", boyut_format(f$olcu_bayt)),
                  div(class = "sened-nom", f$orijinal_ad),
                  div(class = "sened-meta",
                      glue("SHA: {substr(f$sha256, 1, 12)}..."))
              )
            })
          )
        } else {
          p(class = "text-muted", "Bu sənədə fayl əlavə edilməyib.")
        }
      )
    })

    # ---- Yükləmə ----
    observeEvent(input$yukle, {
      f <- input$fayl
      if (is.null(f) || nrow(f) == 0) {
        showNotification("Fayl seçin.", type = "warning")
        return()
      }

      nov <- input$nov
      if (!nzchar(nov)) {
        showNotification("Sənəd növünü seçin.", type = "warning")
        return()
      }

      withProgress(message = "Sənəd göndərilir...", value = 0.3, {

        for (i in seq_len(nrow(f))) {
          fayl_yolu <- f$datapath[i]
          orijinal  <- f$name[i]
          mime      <- f$type[i]

          # FastAPI-yə göndər
          tryCatch({
            netice <- httr2::request(paste0(KFG$api_url, "/senedler/yukle")) |>
              httr2::req_body_multipart(
                fayl       = curl::form_file(fayl_yolu, type = mime, name = orijinal),
                nov        = nov,
                nomre      = input$nomre,
                sened_tarixi = format(input$tarix, "%Y-%m-%d"),
                qarsi_teref = input$teref,
                qeyd        = input$qeyd,
                daxil_eden  = Sys.info()[["user"]]
              ) |>
              httr2::req_timeout(120) |>
              httr2::req_perform() |>
              httr2::resp_body_json()

            yukle_melumat(netice)
            jurnal("[SƏNƏD YÜKLƏNDİ] ", orijinal, " → sened_id=", netice$sened_id)

          }, error = function(e) {
            jurnal("[YÜKLƏMƏ XƏTASI] ", orijinal, ": ", conditionMessage(e))
            showNotification(glue("Xəta: {conditionMessage(e)}"), type = "error")
          })
        }

        setIncProgress(0.9)
      })

      showNotification(
        glue("{nrow(f)} fayl göndərildi. AI analiz növbəsindədir."),
        type = "message", duration = 6
      )

      # Formu təmizlə
      updateTextInput(session, "nomre", value = "")
      updateTextInput(session, "teref", value = "")
      updateTextAreaInput(session, "qeyd", value = "")
    })

    output$yukle_netice <- renderUI({
      m <- yukle_melumat()
      if (is.null(m)) return(NULL)
      div(style = "background:#f0fdf4; padding:10px; border-radius:6px; font-size:13px; margin-top:8px;",
          icon("check-circle", style = "color:#5bd08a;"),
          glue(" Sənəd #{m$sened_id} yaradıldı. AI növbəsindədir."))
    })

  })
}
