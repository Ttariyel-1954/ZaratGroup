# ==============================================================================
# İSTEHSAL MODULU — Faza 3
# Sifarişlər, reseptlər, sapma hesabatı
# ==============================================================================

mod_istehsal_UI <- function(id) {
  ns <- NS(id)

  tagList(
    navset_tab(
      nav_panel("Sifarişlər",
        layout_columns(
          col_widths = c(4, 8),
          card(
            card_header("Yeni sifariş"),
            uiOutput(ns("resept_secim")),
            numericInput(ns("planlanan"), "Planlanmış miqdar (kq)", value = NULL, min = 0),
            textInput(ns("partiya"), "Partiya №", placeholder = "2026-07-13-A"),
            actionButton(ns("sifaris_yarat"), "Sifariş yarat",
                         class = "btn-primary btn-idare")
          ),
          card(
            card_header(tagList(
              "Aktiv sifarişlər",
              actionButton(ns("sifaris_yenile"), icon("rotate"),
                           class = "btn-sm btn-outline-secondary float-end")
            )),
            DTOutput(ns("sifarisler"))
          )
        )
      ),

      nav_panel("Sapma hesabatı",
        layout_columns(
          col_widths = c(3, 9),
          card(
            card_header("Sifariş seç"),
            uiOutput(ns("sapma_sifaris_secim")),
            uiOutput(ns("sapma_ozet"))
          ),
          card(
            card_header("Resept vs Faktiki"),
            plotlyOutput(ns("sapma_qrafik"), height = "400px"),
            br(),
            uiOutput(ns("sapma_cedvel_ui"))
          )
        )
      ),

      nav_panel("Reseptlər",
        card(
          card_header("Resept kataloquu"),
          DTOutput(ns("reseptler"))
        )
      )
    )
  )
}

mod_istehsal_Server <- function(id, taymer) {
  moduleServer(id, function(input, output, session) {

    # ---- Resept seçimi ----
    output$resept_secim <- renderUI({
      d <- sorgu("merkez", "SELECT kod, ad FROM istehsal.resept WHERE aktiv ORDER BY ad")
      if (is.null(d) || nrow(d) == 0)
        return(p(class = "text-muted", "Resept tapılmadı."))
      selectInput(session$ns("resept_kod"), "Resept",
                  choices = setNames(d$kod, paste0(d$kod, " — ", d$ad)))
    })

    output$reseptler <- renderDT({
      d <- sorgu("merkez", "
        SELECT r.kod AS \"Kod\", r.ad AS \"Ad\",
               r.baza_miqdar AS \"Baza miqdar\", r.mehsul_vahid AS \"Vahid\",
               r.versiya AS \"Versiya\",
               count(t.id) AS \"Terkib say\"
        FROM istehsal.resept r
        LEFT JOIN istehsal.resept_terkib t ON t.resept_kod = r.kod
        WHERE r.aktiv
        GROUP BY r.kod, r.ad, r.baza_miqdar, r.mehsul_vahid, r.versiya
        ORDER BY r.ad
      ")
      if (is.null(d)) d <- data.frame(Vəziyyət = "Mərkəz əlçatmazdır")
      datatable(d, rownames = FALSE, class = "compact stripe hover",
                options = list(pageLength = 20, dom = "ft"))
    })

    # ---- Sifarişlər ----
    sifarisler_data <- reactive({
      taymer()
      input$sifaris_yenile
      sorgu("merkez", "
        SELECT s.id,
               s.resept_kod AS \"Resept\",
               s.planlanan_miqdar AS \"Planlanan\",
               COALESCE(s.faktiki_miqdar::text, '—') AS \"Faktiki\",
               s.partiya_no AS \"Partiya\",
               s.status AS \"Status\",
               to_char(s.yaradilma, 'DD.MM.YYYY HH24:MI') AS \"Yaradıldı\"
        FROM istehsal.sifaris s
        WHERE s.status IN ('planlanib','isleyir')
        ORDER BY s.id DESC
      ")
    })

    output$sifarisler <- renderDT({
      d <- sifarisler_data()
      if (is.null(d)) d <- data.frame(Vəziyyət = "Mərkəz əlçatmazdır")
      goster <- if ("id" %in% names(d)) d[, names(d) != "id"] else d
      datatable(goster, rownames = FALSE, class = "compact stripe hover",
                options = list(pageLength = 10, dom = "ftp"))
    })

    observeEvent(input$sifaris_yarat, {
      req(input$resept_kod, input$planlanan)
      ok <- icra("merkez", "
        INSERT INTO istehsal.sifaris
          (resept_kod, planlanan_miqdar, partiya_no, zavod_kod)
        VALUES ($1, $2, NULLIF($3,''), $4)
      ", params = list(
        input$resept_kod,
        as.numeric(input$planlanan),
        input$partiya,
        KFG$zavod_kod
      ))
      if (ok) {
        showNotification("Sifariş yaradıldı.", type = "message")
        updateNumericInput(session, "planlanan", value = NULL)
        updateTextInput(session, "partiya", value = "")
      } else {
        showNotification("Xəta. Bağlantını yoxlayın.", type = "error")
      }
    })

    # ---- Sapma hesabatı ----
    output$sapma_sifaris_secim <- renderUI({
      d <- sorgu("merkez", "
        SELECT s.id, s.resept_kod, s.partiya_no,
               to_char(s.yaradilma, 'DD.MM.YYYY') AS tarix
        FROM istehsal.sifaris s
        WHERE s.status = 'bitdi'
        ORDER BY s.id DESC LIMIT 30
      ")
      if (is.null(d) || nrow(d) == 0)
        return(p(class = "text-muted", "Tamamlanmış sifariş yoxdur."))
      etiket <- paste0(d$resept_kod, " · ", d$tarix,
                       ifelse(is.na(d$partiya_no), "", paste0(" [", d$partiya_no, "]")))
      selectInput(session$ns("sapma_sifaris_id"), NULL,
                  choices = setNames(d$id, etiket))
    })

    sapma_data <- reactive({
      req(input$sapma_sifaris_id)
      sorgu("merkez", glue("
        WITH sifaris AS (
          SELECT s.id, s.resept_kod, s.planlanan_miqdar, s.faktiki_miqdar,
                 r.baza_miqdar
          FROM istehsal.sifaris s
          JOIN istehsal.resept r ON r.kod = s.resept_kod
          WHERE s.id = { input$sapma_sifaris_id }
        ),
        gozlenilen AS (
          SELECT t.material_kod, m.ad,
                 t.miqdar * (SELECT faktiki_miqdar / baza_miqdar FROM sifaris) AS gozlenilen,
                 t.dozum_faiz
          FROM istehsal.resept_terkib t
          JOIN anbar.material m ON m.kod = t.material_kod
          WHERE t.resept_kod = (SELECT resept_kod FROM sifaris)
        ),
        faktiki AS (
          SELECT material_kod, sum(miqdar) AS faktiki
          FROM anbar.herekat
          WHERE novu = 'MEXARIC'
            AND sifaris_id = { input$sapma_sifaris_id }
          GROUP BY material_kod
        )
        SELECT g.material_kod, g.ad,
               round(g.gozlenilen::numeric, 1) AS gozlenilen,
               COALESCE(round(f.faktiki::numeric, 1), 0) AS faktiki,
               g.dozum_faiz,
               round((COALESCE(f.faktiki, g.gozlenilen) - g.gozlenilen) / g.gozlenilen * 100, 1) AS faiz_ferq
        FROM gozlenilen g
        LEFT JOIN faktiki f ON f.material_kod = g.material_kod
        ORDER BY abs(faiz_ferq) DESC NULLS LAST
      "))
    })

    output$sapma_ozet <- renderUI({
      d <- sapma_data()
      if (is.null(d) || nrow(d) == 0) return(p(class = "text-muted", "Məlumat yoxdur."))

      kritik_say <- sum(abs(d$faiz_ferq) > d$dozum_faiz, na.rm = TRUE)
      reng <- if (kritik_say > 0) "#e5695f" else "#5bd08a"
      div(
        div(style = glue("color:{reng}; font-size:22px; font-family:Oswald,sans-serif; font-weight:700;"),
            if (kritik_say > 0)
              glue("{kritik_say} material dözüm xaricindədir")
            else "Hamısı dözüm daxilindədir")
      )
    })

    output$sapma_qrafik <- renderPlotly({
      d <- sapma_data()
      req(!is.null(d) && nrow(d) > 0)

      renglar <- ifelse(abs(d$faiz_ferq) > d$dozum_faiz, "#e5695f", "#5bd08a")

      plot_ly(d,
              x = ~reorder(ad, abs(faiz_ferq)),
              y = ~faiz_ferq,
              type = "bar",
              marker = list(color = renglar),
              text = ~paste0(faiz_ferq, "%"),
              hovertemplate = paste0(
                "<b>%{x}</b><br>",
                "Gözlənilən: %{customdata[0]} kq<br>",
                "Faktiki: %{customdata[1]} kq<br>",
                "Fərq: %{y}%<extra></extra>"
              ),
              customdata = ~matrix(c(gozlenilen, faktiki), ncol = 2)
      ) |>
        add_segments(
          x = ~reorder(ad, abs(faiz_ferq)),  xend = ~reorder(ad, abs(faiz_ferq)),
          y = ~-dozum_faiz, yend = ~dozum_faiz,
          line = list(color = "rgba(0,0,0,0.2)", width = 4),
          name = "Dözüm zonası"
        ) |>
        layout(
          xaxis = list(title = "", tickangle = -30),
          yaxis = list(title = "Fərq (%)"),
          plot_bgcolor  = "#fbfaf7",
          paper_bgcolor = "#fbfaf7",
          showlegend = FALSE,
          margin = list(b = 80)
        ) |>
        config(displayModeBar = FALSE)
    })

    output$sapma_cedvel_ui <- renderUI({
      d <- sapma_data()
      if (is.null(d) || nrow(d) == 0) return(NULL)

      goster <- d
      names(goster) <- c("Kod", "Material", "Gözlənilən", "Faktiki", "Dözüm %", "Fərq %")

      div(
        h6("Cədvəl"),
        cedvel_html(goster, "Fərq %")
      )
    })

  })
}
