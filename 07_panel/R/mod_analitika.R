# ==============================================================================
# ANALİTİKA MODULU — Faza 3
# Trendlər, sərfiyyat, AI xərci
# ==============================================================================

mod_analitika_UI <- function(id) {
  ns <- NS(id)

  navset_tab(
    nav_panel("Material sərfiyyatı",
      layout_columns(
        col_widths = c(3, 9),
        card(
          selectInput(ns("mat_material"), "Material",
                      choices = c("Yüklənir..." = "")),
          selectInput(ns("mat_dovr"), "Dövr",
                      choices = c("Son 30 gün" = 30, "Son 90 gün" = 90,
                                  "Son 180 gün" = 180))
        ),
        card(
          card_header("Sərfiyyat trendi"),
          plotlyOutput(ns("serfiyyat_trend"), height = "380px")
        )
      )
    ),

    nav_panel("AI xərci",
      layout_columns(
        col_widths = c(6, 6),
        card(
          card_header("Gündəlik token"),
          plotlyOutput(ns("ai_token_qrafik"), height = "300px")
        ),
        card(
          card_header("Agent üzrə bölgü"),
          plotlyOutput(ns("ai_agent_qrafik"), height = "300px")
        )
      ),
      card(
        card_header("Gündəlik xərc jurnalı"),
        DTOutput(ns("ai_xerc_cedvel"))
      )
    ),

    nav_panel("Enerji / Ton",
      div(style = "padding:40px; text-align:center; color:#9ca3af;",
          icon("flask", style = "font-size:36px; margin-bottom:12px; display:block;"),
          h4("Enerji analitikası — hazırlanır"),
          p("Agent ENERJI_SERFIYYAT aktiv olduqdan sonra burada kWh/ton məhsul",
            "göstəricisi, normadan sapma və trend görünəcək."))
    )
  )
}

mod_analitika_Server <- function(id, taymer) {
  moduleServer(id, function(input, output, session) {

    # ---- Material siyahısını yüklə ----
    observe({
      d <- sorgu("merkez", "SELECT kod, ad FROM anbar.material WHERE aktiv ORDER BY ad")
      if (!is.null(d) && nrow(d) > 0) {
        updateSelectInput(session, "mat_material",
                          choices = setNames(d$kod, paste0(d$kod, " — ", d$ad)))
      }
    })

    # ---- Sərfiyyat trendi ----
    output$serfiyyat_trend <- renderPlotly({
      req(input$mat_material)
      dovr <- as.integer(input$mat_dovr)

      d <- sorgu("merkez", glue("
        SELECT date_trunc('day', vaxt)::date AS gun,
               sum(CASE WHEN novu = 'MEXARIC' THEN miqdar ELSE 0 END) AS serfiyyat,
               sum(CASE WHEN novu = 'MEDAXIL' THEN miqdar ELSE 0 END) AS medaxil
        FROM anbar.herekat
        WHERE material_kod = '{ input$mat_material }'
          AND vaxt > now() - interval '{ dovr } days'
        GROUP BY 1 ORDER BY 1
      "))

      if (is.null(d) || nrow(d) == 0) {
        return(plot_ly() |> layout(
          title = list(text = "Məlumat yoxdur", font = list(size = 13)),
          plot_bgcolor = "#fbfaf7", paper_bgcolor = "#fbfaf7"))
      }

      plot_ly(d, x = ~gun) |>
        add_bars(y = ~serfiyyat, name = "Sərfiyyat",
                 marker = list(color = "#e5695f88")) |>
        add_bars(y = ~medaxil, name = "Mədaxil",
                 marker = list(color = "#5bd08a88")) |>
        layout(
          barmode = "group",
          xaxis   = list(title = ""),
          yaxis   = list(title = "kq"),
          plot_bgcolor  = "#fbfaf7",
          paper_bgcolor = "#fbfaf7",
          legend  = list(orientation = "h", y = -0.15)
        ) |>
        config(displayModeBar = FALSE)
    })

    # ---- AI token qrafiki ----
    output$ai_token_qrafik <- renderPlotly({
      d <- sorgu("merkez", "
        SELECT gun,
               sum(giris_token + cixis_token) AS toplam_token,
               sum(giris_token)               AS giris,
               sum(cixis_token)               AS cixis
        FROM ai.gunluk_xerc
        WHERE gun > now() - interval '30 days'
        GROUP BY gun ORDER BY gun
      ")

      if (is.null(d) || nrow(d) == 0) {
        return(plot_ly() |> layout(title = list(text = "AI çağırışı yoxdur")))
      }

      plot_ly(d, x = ~gun) |>
        add_bars(y = ~giris,  name = "Giriş token",  marker = list(color = "#5aa9e688")) |>
        add_bars(y = ~cixis,  name = "Çıxış token",  marker = list(color = "#0d948888")) |>
        layout(
          barmode = "stack",
          xaxis   = list(title = ""),
          yaxis   = list(title = "Token"),
          plot_bgcolor = "#fbfaf7", paper_bgcolor = "#fbfaf7",
          legend = list(orientation = "h", y = -0.18)
        ) |>
        config(displayModeBar = FALSE)
    })

    # ---- Agent üzrə bölgü ----
    output$ai_agent_qrafik <- renderPlotly({
      d <- sorgu("merkez", "
        SELECT agent_kod,
               sum(giris_token + cixis_token) AS toplam,
               sum(cagiris)                   AS cagiris
        FROM ai.gunluk_xerc
        WHERE gun > now() - interval '30 days'
        GROUP BY agent_kod
        ORDER BY toplam DESC
      ")

      if (is.null(d) || nrow(d) == 0)
        return(plot_ly() |> layout(title = list(text = "AI çağırışı yoxdur")))

      plot_ly(d, labels = ~agent_kod, values = ~toplam, type = "pie",
              textinfo = "label+percent",
              hovertemplate = "<b>%{label}</b><br>%{value} token<extra></extra>") |>
        layout(showlegend = TRUE,
               plot_bgcolor = "#fbfaf7", paper_bgcolor = "#fbfaf7") |>
        config(displayModeBar = FALSE)
    })

    # ---- AI xərc cədvəli ----
    output$ai_xerc_cedvel <- renderDT({
      taymer()
      d <- sorgu("merkez", "
        SELECT to_char(gun, 'DD.MM.YYYY') AS \"Gün\",
               agent_kod AS \"Agent\",
               cagiris AS \"Çağırış\",
               giris_token AS \"Giriş token\",
               cixis_token AS \"Çıxış token\",
               orta_ms AS \"Orta ms\",
               xetali AS \"Xətalı\"
        FROM ai.gunluk_xerc
        ORDER BY gun DESC, cagiris DESC
        LIMIT 50
      ")
      if (is.null(d)) d <- data.frame(Vəziyyət = "Mərkəz əlçatmazdır")
      datatable(d, rownames = FALSE, class = "compact stripe",
                options = list(pageLength = 10, dom = "ftp")) |>
        formatStyle("Xətalı",
                    backgroundColor = styleInterval(0, c("white", "#fef2f2")))
    })

  })
}
