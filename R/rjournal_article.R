#' R Journal format.
#'
#' Format for creating R Journal articles. Adapted from
#' <https://journal.r-project.org/submissions.html>.
#'
#' This file is only a basic article template. For full details of _The R
#' Journal_ style and information on how to prepare your article for submission,
#' see the [Instructions for Authors](https://journal.r-project.org/share/author-guide.pdf)
#'
#' ## About this format and the R Journal requirements
#'
#' `rticles::rjournal_article` will help you build the correct files requirements:
#'
#' - A R file will be generated automatically using `knitr::purl` - see
#' https://bookdown.org/yihui/rmarkdown-cookbook/purl.html for more information.
#' - A tex file will be generated from this Rmd file and correctly included in
#' `RJwapper.tex` as expected to build `RJwrapper.pdf`.
#' - All figure files will be kept in the default rmarkdown `*_files` folder. This
#' happens because `keep_tex = TRUE` by default in `rticles::rjournal_article`
#' - Only the bib filename is to be modified. An example bib file is included in the
#' template (`RJreferences.bib`) and you will have to name your bib file as the
#' tex, R, and pdf files.
#'
#' # About YAML header fields
#'
#' This section documents some of the YAML fields that can be used with this
#' formats.
#'
#' ## The `author` field in the YAML header
#'
#' | FIELD  | TYPE | DESCRIPTION |
#' | ------ | ---- | ----------- |
#' | `name` | *required* | name and surname of the author |
#' | `affiliation` | *required* | name of the author's affiliation |
#' | `address` | *required* | at least one address line for the affiliation |
#' | `url` | *optional* | an additional url for the author or the main affiliation |
#' | `orcid` | *optional* | the authors ORCID if available |
#' | `email` | *required* | the author's e-mail address |
#' | `affiliation2` | *optional* | name of the author's 2nd affiliation |
#' | `address2` | *optional* | address lines belonging to the author's 2nd affiliation |
#'
#' *Please note: Only one `url`, `orcid` and `email` can be provided per author.*
#'
#' ## Other YAML fields
#'
#' | FIELD | TYPE | DESCRIPTION |
#' | ----- | ---- | ----------- |
#' | `bibliography` | *with default* | the BibTeX file with the reference entries |
#'
#' @inheritParams rmarkdown::pdf_document
#' @param ... Arguments to [rmarkdown::pdf_document()].
#' @export
rjournal_article <- function(..., keep_tex = TRUE, citation_package = 'natbib') {

  rmarkdown::pandoc_available('2.2', TRUE)

  base <- pdf_document_format(
    "rjournal", highlight = NULL, citation_package = citation_package,
    keep_tex = keep_tex, ...
  )

  # Render will generate tex file, post-knit hook gerenates the R file,
  # post-process hook generates appropriate RJwrapper.tex and
  # use pandoc to build pdf from that
  base$pandoc$to <- "latex"
  base$pandoc$ext <- ".tex"

  # Generates R file expected by R journal requirement.
  # We do that in the post-knit hook do access input file path.
  pk <- base$post_knit
  output_R <- NULL
  base$post_knit <- function(metadata, input_file, runtime, ...) {
    # run post_knit it exists
    if (is.function(pk)) pk(metadata, input_file, runtime, ...)

    # purl the Rmd file to R code per requirement
    temp_R <- tempfile(fileext = ".R")
    output_R <<- knitr::purl(input_file, temp_R, documentation = 1, quiet = TRUE)
    # Add magic comment about '"do not edit" (rstudio/rstudio#2082)
    xfun::write_utf8(c(
      "# Generated by `rjournal_article()` using `knitr::purl()`: do not edit by hand",
      sprintf("# Please edit %s to modify this file", input_file),
      "",
      xfun::read_utf8(output_R)
    ), output_R)

    NULL
  }

  base$post_processor <- function(metadata, utf8_input, output_file, clean, verbose) {
    filename <- basename(output_file)
    # underscores in the filename will be problematic in \input{filename};
    # pandoc will escape underscores but it should not, i.e., should be
    # \input{foo_bar} instead of \input{foo\_bar}
    if (filename != (filename2 <- gsub('_', '-', filename))) {
      file.rename(filename, filename2); filename <- filename2
    }

    # Copy purl-ed R file with the correct name
    dest_file <- xfun::with_ext(filename, "R")
    our_file <- TRUE
    if (file.exists(dest_file)) {
      # we check this file is generated by us
      # otherwise we leave it as is and warn
      current_r <- xfun::read_utf8(dest_file)
      our_file <- grepl("Generated.*rjournal_article.*do not edit by hand", current_r[1])
      if (!our_file) {
        warning(
          sprintf("R file with name '%s' already exists.", dest_file),
          "\nIt will not be overwritten by the one generated",
          " during rendering using `knitr::purl()`.",
          "\nRemove the existing file to obtain the generated one.",
          call. = FALSE
        )
      }
    }
    if (our_file) {
      # we only overwrite if it is our file
      file.copy(output_R, xfun::with_ext(filename, "R"), overwrite = TRUE)
    }
    unlink(output_R)

    # post process TEX file
    temp_tex <- xfun::read_utf8(filename)
    temp_tex <- post_process_authors(temp_tex)
    xfun::write_utf8(temp_tex, filename)

    # check bibliography name
    bib_filename <- metadata$bibliography
    if (length(bib_filename) == 1 &&
        xfun::sans_ext(bib_filename) != xfun::sans_ext(filename)) {
      msg <- paste0(
        "Per R journal requirement, bibliography file and tex file should",
        " have the same name. Currently, you have a bib file ", bib_filename,
        " and a tex file ", filename, ". Don't forget to rename and change",
        " the bibliography field in the YAML header."
      )
      warning(msg, call. = FALSE)
    }

    # Create RJwrapper.tex per R Journal requirement
    m <- list(filename = xfun::sans_ext(filename))
    h <- get_list_element(metadata, c('output', 'rticles::rjournal_article', 'includes', 'in_header'))
    h <- c(h, if (length(preamble <- unlist(metadata[c('preamble', 'header-includes')]))) {
      f <- tempfile(fileext = '.tex'); on.exit(unlink(f), add = TRUE)
      xfun::write_utf8(preamble, f)
      f
    })
    t <- find_resource("rjournal", "RJwrapper.tex")
    template_pandoc(m, t, "RJwrapper.tex", h, verbose)

    tinytex::latexmk("RJwrapper.tex", base$pandoc$latex_engine, clean = clean)
  }

  # Mostly copied from knitr::render_sweave
  base$knitr$opts_chunk$comment <- "#>"

  set_sweave_hooks(base)
}
