# ==============================================================================
# SENSORLAR MODULU — Faza 2 funksionallığı
# Boru xətti, cihazlar, xəbərdarlıqlar, sinxronizasiya
# ==============================================================================

# ------------------------------------------------------------------------------
# VƏZİYYƏT YIĞICILARI — boru xəttinin hər mərhələsi
# ------------------------------------------------------------------------------

sensorlar_yigi <- function() {
  d <- sorgu("edge", "
    SELECT c.kod, c.ad, c.status, c.yer,
           st.kod AS tip, st.ad AS tip_ad, st.vahid,
           st.min_hedd, st.max_hedd,
           o.son_vaxt, o.son_qiymet,
           EXTRACT(EPOCH FROM (now() - o.son_vaxt))::int AS susma_san
    FROM cihaz c
    LEFT JOIN sensor_tipi st ON st.kod = c.sensor_tipi_kod
    LEFT JOIN LATERAL (
        SELECT olcme_vaxti AS son_vaxt, qiymet AS son_qiymet
        FROM olcme WHERE cihaz_kod = c.kod
        ORDER BY olcme_vaxti DESC LIMIT 1
    ) o ON TRUE
    ORDER BY c.kod
  ")

  if (is.null(d) || nrow(d) == 0) {
    return(list(veziyyet = "bilinmir", reqem = "—", etiket = "Cihazlar",
                detal = "Baza cavab vermir", cedvel = NULL))
  }

  hedd <- KFG$susma_deq * 60
  d$aktiv <- d$status == "aktiv"
  d$susan <- d$aktiv & (is.na(d$susma_san) | d$susma_san > hedd)

  aktiv_say <- sum(d$aktiv)
  susan_say <- sum(d$susan)
  xarab_say <- sum(d$status == "xarab")
  ish       <- aktiv_say - susan_say

  vez <- if (aktiv_say == 0)    "bilinmir"
         else if (susan_say == 0) "ok"
         else if (susan_say < aktiv_say) "xeberdarliq"
         else "kritik"

  detal <- if (susan_say > 0)
    glue("Susan: {paste(d$kod[d$susan], collapse = ', ')}")
  else if (xarab_say > 0)
    glue("Hamısı göndərir · {xarab_say} cihaz xarab kimi işarələnib")
  else "Hamısı məlumat göndərir"

  list(veziyyet = vez,
       reqem    = glue("{ish}/{aktiv_say}"),
       etiket   = "Aktiv cihaz işləyir",
       detal    = detal,
       cedvel   = d)
}

broker_yigi <- function(mtr) {
  isleyir <- proses_var("mosquitto") || port_aciq(KFG$mqtt_host, KFG$mqtt_port)
  qosulub <- !is.null(mtr) && isTRUE(mtr$mqtt$qosulub)

  vez <- if (!isleyir) "kritik" else if (!qosulub) "xeberdarliq" else "ok"

  list(
    veziyyet = vez,
    reqem    = if (!is.null(mtr)) format(mtr$mqtt$gelen %||% 0, big.mark = " ") else "—",
    etiket   = "Mesaj qəbul edildi",
    detal    = if (!isleyir) "Broker sönülüdür"
               else if (!qosulub) "Broker işləyir, FastAPI qoşulmayıb"
               else glue("Port {KFG$mqtt_port} açıqdır")
  )
}

api_yigi <- function(mtr) {
  if (is.null(mtr)) {
    return(list(veziyyet = "kritik", reqem = "—", etiket = "Cavab yoxdur",
                detal = glue("{KFG$api_url} əlçatmazdır")))
  }

  novbe <- mtr$mqtt$novbe_uzunlugu %||% 0
  redd  <- mtr$mqtt$redd            %||% 0
  qebul <- mtr$mqtt$qebul           %||% 0
  xeta  <- mtr$yazici$xeta          %||% 0

  vez <- if (xeta > 0 || novbe > 500) "kritik"
         else if (novbe > 50)         "xeberdarliq"
         else "ok"

  list(veziyyet = vez,
       reqem    = format(qebul, big.mark = " "),
       etiket   = "Ölçmə qəbul edildi",
       detal    = glue("Növbə: {novbe} · Rədd: {redd} · Xəta: {xeta}"),
       metrikalar = mtr)
}

edge_yigi <- function() {
  d <- sorgu("edge", "
    SELECT
        (SELECT count(*) FROM olcme) AS cem,
        (SELECT count(*) FROM olcme
          WHERE olcme_vaxti > now() - interval '1 minute') AS son_deq,
        (SELECT count(*) FROM xeberdarliq WHERE hell_olundu = FALSE) AS aktiv_alert,
        (SELECT count(*) FROM xeberdarliq
          WHERE hell_olundu = FALSE AND seviyye = 'kritik') AS kritik_alert
  ")

  if (is.null(d)) {
    return(list(veziyyet = "kritik", reqem = "—", etiket = "Əlçatmaz",
                detal = "Edge baza cavab vermir"))
  }

  vez <- if (d$kritik_alert[1] > 0) "kritik"
         else if (d$son_deq[1] == 0) "xeberdarliq"
         else "ok"

  list(veziyyet = vez,
       reqem    = format(d$cem[1], big.mark = " "),
       etiket   = "Sətir bazada",
       detal    = glue("Son dəqiqə: {d$son_deq[1]} · Aktiv alert: {d$aktiv_alert[1]}"),
       stat     = d)
}

sync_yigi <- function() {
  isleyir <- proses_var("sync/main.py")

  d <- sorgu("edge", "
    SELECT
        count(*) FILTER (WHERE sync_status = 0) AS gozleyen,
        count(*) FILTER (WHERE sync_status = 1) AS gonderilen,
        COALESCE(EXTRACT(EPOCH FROM (now() -
            min(olcme_vaxti) FILTER (WHERE sync_status = 0)))::int, 0) AS gecikme_san
    FROM olcme
  ")

  if (is.null(d)) {
    return(list(veziyyet = "bilinmir", reqem = "—", etiket = "Bilinmir",
                detal = "Edge baza cavab vermir", isleyir = isleyir))
  }

  gozleyen <- d$gozleyen[1]
  gecikme  <- d$gecikme_san[1]

  vez <- if (!isleyir) "kritik"
         else if (gozleyen > KFG$novbe_hedd || gecikme > KFG$gecikme_hedd_sn) "xeberdarliq"
         else "ok"

  list(veziyyet = vez,
       reqem    = format(gozleyen, big.mark = " "),
       etiket   = "Növbədə gözləyir",
       detal    = if (!isleyir) "Sync işçisi işləmir"
                  else glue("Gecikmə: {gecikme} san. · Göndərilib: {format(d$gonderilen[1], big.mark = ' ')}"),
       isleyir  = isleyir,
       stat     = d)
}

merkez_yigi <- function() {
  d <- sorgu("merkez", glue("
    SELECT
        (SELECT count(*) FROM zavod.olcme WHERE zavod_kod = '{KFG$zavod_kod}') AS olcme,
        (SELECT count(*) FROM zavod.xeberdarliq WHERE zavod_kod = '{KFG$zavod_kod}') AS alert,
        (SELECT max(qebul_vaxti) FROM zavod.olcme WHERE zavod_kod = '{KFG$zavod_kod}') AS son_qebul,
        (SELECT COALESCE(sum(setir_sayi - yeni_setir), 0) FROM zavod.sync_jurnal
          WHERE vaxt > now() - interval '1 hour') AS dublikat_saat
  "))

  if (is.null(d)) {
    return(list(veziyyet = "kritik", reqem = "—", etiket = "Əlçatmaz",
                detal = glue("{KFG$merkez$host}:{KFG$merkez$port} cavab vermir")))
  }

  yas <- if (!is.na(d$son_qebul[1]))
    as.numeric(difftime(Sys.time(), d$son_qebul[1], units = "secs")) else NA

  vez <- if (!is.na(yas) && yas > KFG$gecikme_hedd_sn) "xeberdarliq" else "ok"

  list(veziyyet = vez,
       reqem    = format(d$olcme[1], big.mark = " "),
       etiket   = "Sətir mərkəzdə",
       detal    = if (is.na(yas)) "Hələ data çatmayıb"
                  else glue("Son qəbul: {round(yas)} san. əvvəl · Alert: {d$alert[1]}"),
       stat     = d)
}

# ------------------------------------------------------------------------------
# VİZUALLAŞDIRMA
# ------------------------------------------------------------------------------

svg_qrafik <- function(x, y, hedler = NULL, vahid = "", en = 820, boy = 300) {
  if (length(y) == 0 || all(is.na(y))) {
    return(div(style = "padding:50px; text-align:center; color:#7a8a99;",
               "Bu dövrdə məlumat yoxdur."))
  }

  kenar <- list(sol = 52, sag = 16, ust = 16, alt = 30)
  pw <- en - kenar$sol - kenar$sag
  ph <- boy - kenar$ust - kenar$alt

  hamisi <- c(y, unlist(hedler))
  ymin <- min(hamisi, na.rm = TRUE)
  ymax <- max(hamisi, na.rm = TRUE)
  if (ymax == ymin) { ymax <- ymax + 1; ymin <- ymin - 1 }
  pay  <- (ymax - ymin) * 0.08
  ymin <- ymin - pay; ymax <- ymax + pay

  xn   <- as.numeric(x)
  xmin <- min(xn); xmax <- max(xn)
  if (xmax == xmin) xmax <- xmin + 1

  px <- function(v) kenar$sol + (as.numeric(v) - xmin) / (xmax - xmin) * pw
  py <- function(v) kenar$ust + (ymax - v) / (ymax - ymin) * ph

  noqteler <- paste0(round(px(xn), 1), ",", round(py(y), 1), collapse = " ")

  bolgu <- pretty(c(ymin, ymax), n = 5)
  bolgu <- bolgu[bolgu >= ymin & bolgu <= ymax]
  y_oxu <- lapply(bolgu, function(b) {
    tagList(
      tags$line(x1 = kenar$sol, y1 = py(b), x2 = en - kenar$sag, y2 = py(b),
                stroke = "#e3ded4", `stroke-width` = "1"),
      tags$text(x = kenar$sol - 8, y = py(b) + 4, `text-anchor` = "end",
                fill = "#8a97a4", style = "font-size:11px;font-family:monospace;",
                format(b))
    )
  })

  hedd_xett <- list()
  if (!is.null(hedler)) {
    for (h in names(hedler)) {
      v <- hedler[[h]]
      if (is.na(v)) next
      reng <- if (h == "yuxari") "#e5695f" else "#5aa9e6"
      hedd_xett[[length(hedd_xett) + 1]] <- tagList(
        tags$line(x1 = kenar$sol, y1 = py(v), x2 = en - kenar$sag, y2 = py(v),
                  stroke = reng, `stroke-width` = "1.5", `stroke-dasharray` = "6,4"),
        tags$text(x = en - kenar$sag - 4, y = py(v) - 5, `text-anchor` = "end",
                  fill = reng, style = "font-size:10px;font-family:monospace;",
                  paste0(h, ": ", v))
      )
    }
  }

  x_etiket <- lapply(c(0, 0.5, 1), function(f) {
    v <- xmin + f * (xmax - xmin)
    tags$text(x = px(v), y = boy - 8,
              `text-anchor` = if (f == 0) "start" else if (f == 1) "end" else "middle",
              fill = "#8a97a4", style = "font-size:10px;font-family:monospace;",
              format(as.POSIXct(v, origin = "1970-01-01"), "%d.%m %H:%M"))
  })

  tags$svg(
    viewBox = paste(0, 0, en, boy), width = "100%", height = boy,
    xmlns   = "http://www.w3.org/2000/svg",
    style   = "display:block;",
    y_oxu, hedd_xett,
    tags$polyline(points = noqteler, fill = "none",
                  stroke = "#0d9488", `stroke-width` = "1.8",
                  `stroke-linejoin` = "round"),
    x_etiket,
    tags$text(x = 6, y = 12, fill = "#5a6b7c",
              style = "font-size:11px;font-family:monospace;", vahid)
  )
}

cedvel_html <- function(d, vurgu_sutun = NULL) {
  if (is.null(d) || nrow(d) == 0) {
    return(div(style = "padding:26px; text-align:center; color:#7a8a99;",
               "Məlumat yoxdur."))
  }

  setir_sinif <- function(i) {
    if (!is.null(vurgu_sutun) && vurgu_sutun %in% names(d)) {
      v <- as.character(d[[vurgu_sutun]][i])
      if (identical(v, "kritik"))     return("kritik")
      if (identical(v, "xeberdarliq")) return("xeber")
    }
    ""
  }

  div(class = "cdv-sar",
      tags$table(class = "cdv",
        tags$thead(tags$tr(lapply(names(d), tags$th))),
        tags$tbody(
          lapply(seq_len(nrow(d)), function(i) {
            tags$tr(class = setir_sinif(i),
                    lapply(names(d), function(s) {
                      v <- d[[s]][i]
                      tags$td(if (is.na(v)) "—" else as.character(v))
                    }))
          })
        )
      )
  )
}

# ------------------------------------------------------------------------------
# DİAQNOSTİKA — qaydalar əsasında problem tespiti
# ------------------------------------------------------------------------------

diaqnoz <- function(st) {
  p    <- list()
  qeyd <- function(kod, seviyye, basliq, ne_olub, niye, hell, emr = NULL) {
    p[[length(p) + 1]] <<- list(
      kod = kod, seviyye = seviyye, basliq = basliq,
      ne_olub = ne_olub, niye = niye, hell = hell, emr = emr
    )
  }

  if (st$broker$veziyyet == "kritik") {
    qeyd("BROKER_SONUB", "kritik", "MQTT broker işləmir",
         "Sensorların məlumatı gedəcək yer yoxdur.",
         "Mosquitto sönüb — sensorlarla proqram arasındakı körpü yoxdur.",
         c("«Broker başlat» düyməsini basın.", "20 saniyə gözləyin."),
         "brew services start mosquitto")
  } else if (st$broker$veziyyet == "xeberdarliq") {
    qeyd("MQTT_QOSULMAYIB", "xeberdarliq", "Proqram brokerə qoşulmayıb",
         "Broker işləyir, amma FastAPI ondan məlumat oxumur.",
         "Bağlantı qopub. Adətən broker FastAPI-dən sonra başladılanda olur.",
         c("«FastAPI yenidən başlat» düyməsini basın."), NULL)
  }

  if (st$api$veziyyet == "kritik" && is.null(st$api$metrikalar)) {
    qeyd("API_CAVABSIZ", "kritik", "Emal proqramı cavab vermir",
         "Sensor məlumatı heç yerə yazılmır.",
         "FastAPI olmasa, zəncir qırılır.",
         c("«FastAPI başlat» düyməsini basın.",
           "Loglar bölməsində api.log-a baxın."), NULL)
  }

  mtr <- st$api$metrikalar
  if (!is.null(mtr)) {
    novbe <- mtr$mqtt$novbe_uzunlugu %||% 0
    if (novbe > 50) {
      qeyd("NOVBE_DOLUR", if (novbe > 500) "kritik" else "xeberdarliq",
           glue("Növbə dolur — {novbe} mesaj gözləyir"),
           "Məlumat gəldiyindən yavaş yazılır.",
           "Baza yavaşlayıb və ya mesaj axını çox sürətlidir.",
           c("Edge bazanın işlədiyini yoxlayın.", "Diskdə yer varmı? df -h"), NULL)
    }
    xeta <- mtr$yazici$xeta %||% 0
    if (xeta > 0) {
      qeyd("YAZMA_XETASI", "kritik",
           glue("Bazaya yazma xətası — {xeta} dəfə"),
           "Bəzi ölçmələr bazaya yazıla bilmir.",
           "Adətən sxem-kod uyğunsuzluğu və ya disk dolub.",
           c("api.log-a baxın.", "Disk: df -h"), NULL)
    }
  }

  if (!is.null(st$sensorlar$cedvel)) {
    d     <- st$sensorlar$cedvel
    susan <- d[d$susan, ]
    if (nrow(susan) > 0) {
      adlar  <- paste(susan$kod, collapse = ", ")
      hamisi <- nrow(susan) == nrow(d)
      qeyd("CIHAZ_SUSUR", if (hamisi) "kritik" else "xeberdarliq",
           glue("Cihaz məlumat göndərmir: {adlar}"),
           glue("{nrow(susan)} cihaz son {KFG$susma_deq} dəqiqədə məlumat göndərməyib."),
           "Cihaz xarab, kabel qırılıb, ya da şəbəkə kəsilib.",
           c("Cihaza fiziki baxın.", "Kabelləri yoxlayın.",
             "Sensorlar bölməsindən cihazı «xarab» kimi işarələyin."), NULL)
    }
  }

  if (!is.null(st$merkez$stat) && !is.na(st$merkez$stat$dublikat_saat[1])) {
    if (st$merkez$stat$dublikat_saat[1] > 100) {
      qeyd("DUBLIKAT", "melumat",
           glue("Son saatda {st$merkez$stat$dublikat_saat[1]} təkrar göndərmə"),
           "Bəzi sətirlər mərkəzə iki dəfə göndərilib.",
           "Bu, XƏTA DEYİL. Şəbəkə titrəyəndə sistem ehtiyatlı davranır.",
           c("Heç nə etməyə ehtiyac yoxdur."), NULL)
    }
  }

  p
}

# ------------------------------------------------------------------------------
# UI FUNKSİYALARI — boru xətti paneli (Panel tabı üçün kontent)
# ------------------------------------------------------------------------------

mod_sensorlar_panel_UI <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("boru_xetti")),
    layout_columns(
      col_widths = c(7, 5),
      card(card_header("Nə baş verir"), uiOutput(ns("problemler"))),
      card(card_header("Cihazlar"),      uiOutput(ns("cihaz_kartlari")))
    )
  )
}

mod_sensorlar_cihazlar_UI <- function(id) {
  ns <- NS(id)
  layout_columns(
    col_widths = c(3, 9),
    card(
      card_header("Seçim"),
      uiOutput(ns("cihaz_secim")),
      selectInput(ns("saat"), "Dövr",
                  choices  = c("Son 1 saat" = 1, "Son 6 saat" = 6,
                               "Son 24 saat" = 24, "Son 3 gün" = 72),
                  selected = 1),
      hr(),
      uiOutput(ns("cihaz_stat"))
    ),
    card(card_header("Ölçmə axını"),
         plotlyOutput(ns("trend"), height = "440px"))
  )
}

mod_sensorlar_alertler_UI <- function(id) {
  ns <- NS(id)
  layout_columns(
    col_widths = c(12),
    card(
      card_header("Aktiv xəbərdarlıqlar — həll olunmayanlar"),
      DTOutput(ns("alert_aktiv")),
      br(),
      div(style = "display:flex; gap:10px; align-items:center; flex-wrap:wrap;",
          numericInput(ns("alert_id"), "Xəbərdarlıq nömrəsi",
                       value = NULL, min = 1, step = 1, width = "170px"),
          actionButton(ns("alert_hell"), "Həll olundu kimi işarələ",
                       class = "btn-warning", icon = icon("check")),
          span(class = "text-muted", style = "font-size:13px;",
               "Problemi aradan qaldırdıqdan sonra. Dəyər normaya qayıdanda sistem özü bağlayır.")
      )
    ),
    card(card_header("Tarixçə — son 100"),
         DTOutput(ns("alert_tarixce")))
  )
}

mod_sensorlar_sync_UI <- function(id) {
  ns <- NS(id)
  layout_columns(
    col_widths = c(6, 6),
    card(card_header("Növbənin dərinliyi"), plotlyOutput(ns("sync_qrafik"), height = "290px")),
    card(card_header("Vəziyyət"),           uiOutput(ns("sync_veziyyet")))
  ),
  card(card_header("Göndərmə jurnalı — mərkəzdən"),
       DTOutput(ns("sync_jurnal")))
}

# ------------------------------------------------------------------------------
# SERVER
# ------------------------------------------------------------------------------

mod_sensorlar_Server <- function(id, veziyyet, problemler, saglamliq,
                                  novbe_tarixce, taymer) {
  moduleServer(id, function(input, output, session) {

    # ---- Boru xətti ----
    output$boru_xetti <- renderUI({
      qoru("boru_xetti", {
        st <- veziyyet()
        m <- list(
          list(ad = "Sensorlar",       d = st$sensorlar),
          list(ad = "Məlumat qutusu",  d = st$broker),
          list(ad = "Emal proqramı",   d = st$api),
          list(ad = "Zavod bazası",    d = st$edge),
          list(ad = "Göndərici",       d = st$sync),
          list(ad = "Bakı — ERP",      d = st$merkez)
        )

        elementler <- list()
        for (i in seq_along(m)) {
          k <- m[[i]]
          elementler[[length(elementler) + 1]] <- div(
            class = paste("merhele", k$d$veziyyet),
            div(class = paste("lampa", k$d$veziyyet)),
            div(class = "ad",  k$ad),
            div(class = "req", k$d$reqem),
            div(class = "et",  k$d$etiket),
            div(class = "dt",  k$d$detal)
          )
          if (i < length(m)) {
            axir <- k$d$veziyyet %in% c("ok", "xeberdarliq") &&
              m[[i + 1]]$d$veziyyet %in% c("ok", "xeberdarliq")
            elementler[[length(elementler) + 1]] <- div(
              class = if (axir) "seqment" else "seqment dur"
            )
          }
        }
        div(class = "boru", div(class = "boru-sira", elementler))
      })
    })

    # ---- Problemlər ----
    output$problemler <- renderUI({
      p <- problemler()
      if (length(p) == 0) {
        return(div(class = "her-sey-yaxsi",
                   div(class = "b", "Hər şey qaydasındadır"),
                   div("Məlumat sensorlardan Bakıya problemsiz axır.")))
      }
      sira <- c(kritik = 1, xeberdarliq = 2, melumat = 3)
      p    <- p[order(sira[sapply(p, `[[`, "seviyye")])]
      lapply(p, function(x) {
        div(class = paste("problem", x$seviyye),
            h4(x$basliq, span(class = paste("rozet", x$seviyye),
                              switch(x$seviyye, kritik = "Kritik",
                                     xeberdarliq = "Diqqət", melumat = "Məlumat"))),
            div(class = "ne",   x$ne_olub),
            div(class = "niye", strong("Niyə: "), x$niye),
            tags$ol(lapply(x$hell, tags$li))
        )
      })
    })

    # ---- Cihaz kartları ----
    output$cihaz_kartlari <- renderUI({
      d <- veziyyet()$sensorlar$cedvel
      if (is.null(d)) return(p(class = "text-muted", "Baza cavab vermir."))

      lapply(seq_len(nrow(d)), function(i) {
        r     <- d[i, ]
        sinif <- if (isTRUE(r$susan))  "cihaz susur"
                 else if (r$status != "aktiv") "cihaz xarab"
                 else "cihaz"
        alt   <- if (r$status == "xarab")   "XARAB kimi işarələnib"
                 else if (r$status == "deaktiv") "Deaktivdir"
                 else if (isTRUE(r$susan))
                   glue("SUSUR — {if (is.na(r$susma_san)) 'heç vaxt' else paste(round(r$susma_san/60), 'dəqiqədir')}")
                 else glue("{round(r$susma_san)} saniyə əvvəl")

        div(class = sinif,
            div(class = "deyer",
                if (is.na(r$son_qiymet)) "—" else format(round(r$son_qiymet, 1), nsmall = 1),
                span(class = "vahid", paste0(" ", r$vahid %||% ""))
            ),
            div(class = "kod", paste(r$kod, "·", r$tip %||% "")),
            div(class = "tip", alt),
            if (!is.na(r$yer) && nzchar(r$yer))
              div(style = "font-size:11px; color:#94a3b8; margin-top:2px;", r$yer)
        )
      })
    })

    # ---- Cihaz seçimi ----
    output$cihaz_secim <- renderUI({
      d <- veziyyet()$sensorlar$cedvel
      if (is.null(d)) return(NULL)
      etiketler <- paste0(d$kod, " — ", d$tip,
                          ifelse(d$status == "aktiv", "", paste0(" (", d$status, ")")))
      kodlar <- setNames(d$kod, etiketler)
      radioButtons(session$ns("cihaz"), "Cihaz", choices = kodlar,
                   selected = input$cihaz %||% d$kod[1])
    })

    output$cihaz_stat <- renderUI({
      req(input$cihaz)
      saat <- as.integer(input$saat)
      d <- sorgu("edge", glue("
        SELECT count(*) n, round(avg(qiymet),2) orta,
               round(min(qiymet),2) minq, round(max(qiymet),2) maxq,
               count(*) FILTER (WHERE keyfiyyet = 0) anomal
        FROM olcme
        WHERE cihaz_kod = '{input$cihaz}'
          AND olcme_vaxti > now() - interval '{saat} hours'
      "))
      if (is.null(d) || d$n[1] == 0)
        return(p(class = "text-muted", "Bu dövrdə məlumat yoxdur."))

      tags$table(class = "table table-sm",
        tags$tr(tags$td("Ölçmə"), tags$td(tags$b(format(d$n[1], big.mark = " ")))),
        tags$tr(tags$td("Orta"),  tags$td(tags$b(d$orta[1]))),
        tags$tr(tags$td("Ən az"), tags$td(d$minq[1])),
        tags$tr(tags$td("Ən çox"),tags$td(d$maxq[1])),
        tags$tr(tags$td("Anomal"),
                tags$td(tags$b(style = if (d$anomal[1] > 0) "color:#e5695f;" else "",
                               d$anomal[1])))
      )
    })

    output$trend <- renderPlotly({
      req(input$cihaz)
      saat <- as.integer(input$saat)
      d <- sorgu("edge", glue("
        SELECT olcme_vaxti, qiymet, keyfiyyet
        FROM olcme
        WHERE cihaz_kod = '{input$cihaz}'
          AND olcme_vaxti > now() - interval '{saat} hours'
        ORDER BY olcme_vaxti
      "))
      h <- sorgu("edge", glue("
        SELECT st.min_hedd, st.max_hedd, st.vahid, st.ad
        FROM cihaz c JOIN sensor_tipi st ON st.kod = c.sensor_tipi_kod
        WHERE c.kod = '{input$cihaz}'
      "))

      if (is.null(d) || nrow(d) == 0) {
        return(plot_ly() |> layout(
          title = list(text = "Bu dövrdə məlumat yoxdur", font = list(size = 14)),
          plot_bgcolor = "#fbfaf7", paper_bgcolor = "#fbfaf7"))
      }

      p2 <- plot_ly(d, x = ~olcme_vaxti) |>
        add_lines(y = ~qiymet, name = "Ölçmə",
                  line = list(color = "#0d9488", width = 1.6),
                  hovertemplate = "%{y}<br>%{x}<extra></extra>")

      anomal <- d[d$keyfiyyet == 0, ]
      if (nrow(anomal) > 0) {
        p2 <- p2 |> add_markers(data = anomal, x = ~olcme_vaxti, y = ~qiymet,
                                name = "Anomal",
                                marker = list(color = "#e5695f", size = 6))
      }

      if (!is.null(h) && nrow(h) > 0) {
        if (!is.na(h$max_hedd[1]))
          p2 <- p2 |> add_lines(y = h$max_hedd[1], name = "Yuxarı hədd",
                                line = list(color = "#e5695f", dash = "dash", width = 1.2))
        if (!is.na(h$min_hedd[1]))
          p2 <- p2 |> add_lines(y = h$min_hedd[1], name = "Aşağı hədd",
                                line = list(color = "#5aa9e6", dash = "dash", width = 1.2))
      }

      p2 |> layout(
        xaxis  = list(title = "", gridcolor = "#e8e3d8"),
        yaxis  = list(title = if (!is.null(h)) h$vahid[1] else "", gridcolor = "#e8e3d8"),
        hovermode = "x unified",
        plot_bgcolor  = "#fbfaf7", paper_bgcolor = "#fbfaf7",
        legend = list(orientation = "h", y = -0.14),
        margin = list(t = 20)
      ) |> config(displayModeBar = FALSE, locale = "az")
    })

    # ---- Xəbərdarlıqlar ----
    output$alert_aktiv <- renderDT({
      taymer()
      d <- sorgu("edge", "
        SELECT id AS \"№\", cihaz_kod AS \"Cihaz\", novu AS \"Növ\",
               seviyye AS \"Səviyyə\", tetik_sayi AS \"Təkrar\",
               round(pik_qiymet, 2) AS \"Pik dəyər\",
               to_char(acilma_vaxti, 'DD.MM HH24:MI') AS \"Açılıb\",
               mesaj AS \"Mesaj\"
        FROM xeberdarliq
        WHERE hell_olundu = FALSE
        ORDER BY (seviyye = 'kritik') DESC, acilma_vaxti DESC
      ")
      if (is.null(d)) d <- data.frame(Vəziyyət = "Baza cavab vermir")
      if (nrow(d) == 0) d <- data.frame(Vəziyyət = "Aktiv xəbərdarlıq yoxdur")

      dt <- datatable(d, rownames = FALSE, class = "compact stripe hover",
                      options = list(pageLength = 10, dom = "ftp"))
      if ("Səviyyə" %in% names(d)) {
        dt <- dt |> formatStyle("Səviyyə", target = "row",
                                backgroundColor = styleEqual(
                                  c("kritik","xeberdarliq"), c("#fbeceb","#fbf3e2")),
                                fontWeight = styleEqual("kritik", "bold"))
      }
      dt
    })

    output$alert_tarixce <- renderDT({
      taymer()
      d <- sorgu("edge", "
        SELECT id AS \"№\", cihaz_kod AS \"Cihaz\", novu AS \"Növ\",
               seviyye AS \"Səviyyə\", tetik_sayi AS \"Təkrar\",
               to_char(acilma_vaxti, 'DD.MM HH24:MI') AS \"Açılıb\",
               CASE WHEN hell_olundu
                    THEN to_char(baglanma_vaxti - acilma_vaxti, 'HH24:MI:SS')
                    ELSE 'davam edir' END AS \"Müddət\",
               CASE WHEN sync_status = 1 THEN 'Bakıdadır' ELSE 'növbədə' END AS \"Mərkəz\"
        FROM xeberdarliq
        ORDER BY id DESC LIMIT 100
      ")
      if (is.null(d)) d <- data.frame(Vəziyyət = "Baza cavab vermir")
      datatable(d, rownames = FALSE, class = "compact stripe hover",
                options = list(pageLength = 15, dom = "ftp"))
    })

    observeEvent(input$alert_hell, {
      id_val <- input$alert_id
      if (is.null(id_val) || length(id_val) == 0 || is.na(id_val)) {
        showNotification("Xəbərdarlıq nömrəsini yazın.", type = "warning")
        return()
      }
      ok <- icra("edge", "
        UPDATE xeberdarliq
        SET hell_olundu = TRUE, baglanma_vaxti = now()
        WHERE id = $1 AND hell_olundu = FALSE
      ", params = list(as.integer(id_val)))

      if (ok) {
        showNotification(glue("№{id_val} bağlandı."), type = "message")
        updateNumericInput(session, "alert_id", value = NULL)
      } else {
        showNotification("Alınmadı — nömrə doğrudurmu?", type = "error")
      }
    })

    # ---- Sync qrafiki ----
    output$sync_qrafik <- renderPlotly({
      t <- novbe_tarixce()
      if (nrow(t) < 2) {
        return(plot_ly() |> layout(
          title = list(text = "Məlumat toplanır...", font = list(size = 13)),
          plot_bgcolor = "#fbfaf7", paper_bgcolor = "#fbfaf7"))
      }

      plot_ly(t, x = ~vaxt, y = ~gozleyen, type = "scatter", mode = "lines",
              fill = "tozeroy", line = list(color = "#5aa9e6", width = 2),
              fillcolor = "rgba(90,169,230,.18)",
              hovertemplate = "%{y} sətir<br>%{x}<extra></extra>") |>
        layout(xaxis = list(title = "", gridcolor = "#e8e3d8"),
               yaxis = list(title = "Gözləyən sətir", gridcolor = "#e8e3d8"),
               plot_bgcolor = "#fbfaf7", paper_bgcolor = "#fbfaf7",
               showlegend = FALSE, margin = list(t = 20)) |>
        config(displayModeBar = FALSE)
    })

    output$sync_veziyyet <- renderUI({
      st <- veziyyet()
      s  <- st$sync; m <- st$merkez

      setir_ui <- function(etiket, deyer, reng = "#1a222c") {
        div(style = "display:flex; justify-content:space-between; padding:9px 0; border-bottom:1px solid #eee;",
            span(style = "color:#5a6b7c;", etiket),
            span(style = glue("font-family:Oswald,sans-serif; font-weight:600; color:{reng};"), deyer))
      }

      tagList(
        setir_ui("Göndərici proqram",
                 if (isTRUE(s$isleyir)) "İşləyir" else "DAYANIB",
                 if (isTRUE(s$isleyir)) "#2f8f5b" else "#c0453a"),
        setir_ui("Növbədə gözləyir", s$reqem),
        setir_ui("Bakıdakı sətir sayı", m$reqem),
        setir_ui("Mərkəzi baza",
                 if (m$veziyyet == "kritik") "ƏLÇATMAZ" else "Əlçatandır",
                 if (m$veziyyet == "kritik") "#c0453a" else "#2f8f5b"),
        br(),
        div(style = "background:#eaf7f0; padding:12px 15px; border-radius:6px; font-size:13.5px;",
            strong("Yadda saxlayın: "),
            "şəbəkə kəsilsə məlumat İTMİR — zavodda gözləyir.")
      )
    })

    output$sync_jurnal <- renderDT({
      taymer()
      d <- sorgu("merkez", glue("
        SELECT to_char(date_trunc('hour', vaxt), 'DD.MM HH24:00') AS \"Saat\",
               cedvel AS \"Cədvəl\",
               count(*) AS \"Dövr\",
               sum(setir_sayi) AS \"Göndərilib\",
               sum(setir_sayi - yeni_setir) AS \"Təkrar\",
               round(avg(muddet_ms)) AS \"Orta ms\"
        FROM zavod.sync_jurnal
        WHERE zavod_kod = '{KFG$zavod_kod}' AND vaxt > now() - interval '24 hours'
        GROUP BY 1, 2 ORDER BY 1 DESC
      "))
      if (is.null(d)) d <- data.frame(Vəziyyət = "Mərkəzi baza əlçatmazdır")
      datatable(d, rownames = FALSE, class = "compact stripe",
                options = list(pageLength = 12, dom = "tp"))
    })

  })
}
