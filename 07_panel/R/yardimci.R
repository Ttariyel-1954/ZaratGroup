# ==============================================================================
# YARDIMÇİ FUNKSİYALAR — bütün modullar istifadə edir
# ==============================================================================

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a

# --- Panelin öz jurnalı ---
# Konsola baxmadan xətanı görmək üçün. Hər şey bura yazılır.
PANEL_LOG <- file.path(LAYIHE_KOK, "_LOG", "panel.log")
dir.create(dirname(PANEL_LOG), showWarnings = FALSE, recursive = TRUE)

jurnal <- function(...) {
  try(cat(format(Sys.time(), "%H:%M:%S"), " ", paste0(...), "\n",
          sep = "", file = PANEL_LOG, append = TRUE), silent = TRUE)
}

# Nəzarət paneli ən çox problem olanda lazımdır — deməli o, çökmüməlidir.
# Hər yığıcı bu örtüyün içindədir: xəta atsa, panel ölmür, xətanı göstərir.
tehlukesiz <- function(ad, f) {
  tryCatch(f(), error = function(e) {
    mesaj <- conditionMessage(e)
    jurnal("[YIĞICI XƏTASI] ", ad, ": ", mesaj)
    list(veziyyet = "bilinmir", reqem = "!", etiket = "Daxili xəta",
         detal = substr(mesaj, 1, 90), xeta = mesaj)
  })
}

# Hər render bunun içindədir. Xəta olsa — ekranda qırmızı mətn + jurnalda iz.
qoru <- function(ad, ifade) {
  tryCatch(ifade, error = function(e) {
    mesaj <- conditionMessage(e)
    jurnal("[RENDER XƏTASI] ", ad, ": ", mesaj)
    div(style = "color:#c0453a; font-family:ui-monospace,monospace; font-size:12px; padding:10px;",
        strong(paste0("XƏTA (", ad, "): ")), mesaj)
  })
}

# Sənəd ölçüsünü oxunaqlı formata çevir
boyut_format <- function(bayt) {
  if (is.na(bayt) || bayt == 0) return("0 B")
  vahidler <- c("B", "KB", "MB", "GB")
  i <- floor(log(bayt, 1024))
  i <- min(i, length(vahidler) - 1)
  paste0(round(bayt / 1024^i, 1), " ", vahidler[i + 1])
}

# Fayl MIME tipinə görə ikon
mime_ikon <- function(mime) {
  switch(mime,
    "application/pdf" = "📄",
    "image/jpeg" = "🖼️",
    "image/png"  = "🖼️",
    "image/webp" = "🖼️",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "📊",
    "application/vnd.ms-excel" = "📊",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "📝",
    "📎"
  )
}
