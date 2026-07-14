# ==============================================================================
# ANBAR MODULU — Faza 3
# Qalıq, hərəkat, min_qaliq xəbərdarlıqları
# ==============================================================================

mod_anbar_UI <- function(id) {
  ns <- NS(id)

  layout_columns(
    col_widths = c(4, 8),

    card(
      card_header("Materiallar"),
      uiOutput(ns("qaliq_kartlar"))
    ),

    tagList(
      card(
        card_header(tagList(
          "Qalıq cədvəli",
          actionButton(ns("yenile"), icon("rotate"),
                       class = "btn-sm btn-outline-secondary float-end")
        )),
        DTOutput(ns("qaliq_cedvel"))
      ),
      card(
        card_header("Hərəkat tarixçəsi — seçili material"),
        uiOutput(ns("material_secim")),
        DTOutput(ns("herekat_cedvel"))
      )
    )
  )
}

mod_anbar_Server <- function(id, taymer) {
  moduleServer(id, function(input, output, session) {

    secili_material <- reactiveVal(NULL)

    qaliq_data <- reactive({
      taymer()
      input$yenile
      sorgu("merkez", "
        SELECT kod, ad, vahid,
               COALESCE(min_qaliq, 0) AS min_qaliq,
               qaliq,
               CASE WHEN qaliq <= COALESCE(min_qaliq, 0) THEN 'asagi' ELSE 'normal' END AS veziyyet,
               to_char(son_herekat, 'DD.MM.YYYY HH24:MI') AS son_herekat
        FROM anbar.qaliq
        ORDER BY veziyyet DESC, ad
      ")
    })

    # ---- Kart baxışı ----
    output$qaliq_kartlar <- renderUI({
      d <- qaliq_data()
      if (is.null(d) || nrow(d) == 0) {
        return(p(class = "text-muted", "Anbar məlumatı yoxdur."))
      }

      lapply(seq_len(nrow(d)), function(i) {
        r   <- d[i, ]
        vez <- r$veziyyet
        div(class = paste("anbar-kart", vez),
            div(class = "sened-nov", r$ad),
            div(class = "qaliq-reqem",
                format(round(r$qaliq, 1), big.mark = " "),
                span(style = "font-size:14px; font-weight:400; color:#6b7280;",
                     paste0(" ", r$vahid))),
            if (vez == "asagi")
              div(style = "font-size:12px; color:#e5695f; margin-top:4px;",
                  icon("triangle-exclamation"),
                  glue(" Min hədd: {r$min_qaliq} {r$vahid}"))
        )
      })
    })

    # ---- Cədvəl baxışı ----
    output$qaliq_cedvel <- renderDT({
      d <- qaliq_data()
      if (is.null(d) || !("ad" %in% names(d))) {
        return(datatable(data.frame(Xəbər = "Mərkəz əlçatmazdır"), rownames = FALSE))
      }

      SUTUNLAR <- c(ad = "Material", vahid = "Vahid", qaliq = "Qalıq",
                    min_qaliq = "Min hədd", son_herekat = "Son hərəkat")
      goster <- setNames(d[, names(SUTUNLAR), drop = FALSE], SUTUNLAR)

      datatable(
        goster,
        rownames  = FALSE,
        selection = "single",
        class     = "compact stripe hover",
        options   = list(pageLength = 20, dom = "ft")
      ) |>
        formatStyle(SUTUNLAR[["qaliq"]], SUTUNLAR[["min_qaliq"]],
                    backgroundColor = styleInterval(0, c("#fef2f2", "white")),
                    target = "row")
    })

    observeEvent(input$qaliq_cedvel_rows_selected, {
      d <- qaliq_data()
      if (is.null(d) || length(input$qaliq_cedvel_rows_selected) == 0) {
        secili_material(NULL)
        return()
      }
      secili_material(d$kod[input$qaliq_cedvel_rows_selected])
    })

    output$material_secim <- renderUI({
      d <- qaliq_data()
      if (is.null(d)) return(NULL)
      secim <- setNames(d$kod, d$ad)
      selectInput(session$ns("material_kod"), NULL,
                  choices  = secim,
                  selected = secili_material())
    })

    observe({
      req(input$material_kod)
      secili_material(input$material_kod)
    })

    output$herekat_cedvel <- renderDT({
      req(secili_material())
      d <- sorgu("merkez", glue("
        SELECT to_char(vaxt, 'DD.MM.YYYY HH24:MI') AS \"Vaxt\",
               novu AS \"Növ\",
               CASE novu
                 WHEN 'MEDAXIL' THEN '+' || miqdar
                 WHEN 'MEXARIC' THEN '-' || miqdar
                 ELSE '±' || miqdar
               END AS \"Miqdar\",
               vahid_qiymet AS \"Vahid qiymət\",
               qeyd AS \"Qeyd\"
        FROM anbar.herekat
        WHERE material_kod = '{ secili_material() }'
        ORDER BY vaxt DESC LIMIT 100
      "))
      if (is.null(d)) d <- data.frame(Vəziyyət = "Mərkəz əlçatmazdır")
      datatable(d, rownames = FALSE, class = "compact stripe",
                options = list(pageLength = 10, dom = "ftp"))
    })

  })
}
