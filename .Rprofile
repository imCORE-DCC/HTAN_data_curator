.First <- function() {
  options(
    repos = c(
      CRAN = "https://cran.rstudio.com/",
      Sage = "http://ran.synapse.org"
    )
  )
}

venv_python = file.path(getwd(), "venv/bin/python")
if (file.exists(venv_python)) {
  Sys.setenv(RETICULATE_PYTHON = venv_python)
}

if (interactive()) {
  options(shiny.port = 8787)
}

options(stringsAsFactors = FALSE)
source("renv/activate.R")

