# This is the server logic for a Shiny web application.
# You can find out more about building applications with Shiny here:
#
# http://shiny.rstudio.com
#
# This server has been modified to be used specifically on Sage Bionetworks Synapse pages
# to log into Synapse as the currently logged in user from the web portal using the session token.
#
# https://www.synapse.org

library(shiny)
library(shinyjs)
library(dplyr)
library(shinythemes)
library(shinydashboard)
library(stringr)
library(DT)
library(jsonlite)
library(reticulate)
library(ggplot2)
library(purrr)
library(plotly)
library(shinypop)
library(waiter)
library(readr)

# Don't necessarily have to set `RETICULATE_PYTHON` env variable
reticulate::use_condaenv("data_curator_env_oauth")

shinyServer(function(input, output, session) {
  ########### session global variables
  source_python("python/synapse_func_alias.py")
  source_python("python/metadata_model.py")

  params <- parseQueryString(isolate(session$clientData$url_search))
  if (!has_auth_code(params)) {
    return()
  }
  redirect_url <- paste0(
    api$access, "?", "redirect_uri=",
    APP_URL, "&grant_type=",
    "authorization_code", "&code=", params$code
  )
  # get the access_token and userinfo token
  req <- POST(redirect_url,
    encode = "form",
    body = "",
    authenticate(app$key, app$secret, type = "basic"),
    config = list()
  )
  # Stop the code if anything other than 2XX status code is returned
  stop_for_status(req, task = "get an access token")
  token_response <- content(req, type = NULL)
  access_token <- token_response$access_token

  # import module that contains SynapseStorage class
  synapse_driver <- import("schematic.store.synapse")

  ### read config in
  config <- jsonlite::fromJSON("www/config.json")

  ### logs in and gets list of projects they have access to
  synStore_obj <- NULL
  # get_projects_list(synStore_obj)
  projects_list <- c()

  projects_namedList <- c()

  proj_folder_manifest_cells <- c()

  folder_synID <- NULL

  filename_list <- c()
  ############

  ### synapse cookies
  session$sendCustomMessage(type = "readCookie", message = list())

  ### initial login front page items
  observeEvent(input$cookie, {
    ## login and update session; otherwise, notify to login to Synapse first
    tryCatch(
      {
        ### logs in
        syn_login(sessionToken = input$cookie, rememberMe = FALSE)

        ### welcome message
        output$title <- renderUI({
          titlePanel(h4(sprintf(
            "Welcome, %s", syn_getUserProfile()$userName
          )))
        })

        ### updating global vars with values for projects
        # synStore_obj <<- synapse_driver$SynapseStorage(config$main_fileview, token = input$cookie)
        synStore_obj <<- synapse_driver$SynapseStorage(token = input$cookie)

        # get_projects_list(synStore_obj)
        projects_list <<- synapse_driver$SynapseStorage$getStorageProjects(synStore_obj)

        for (i in seq_along(projects_list)) {
          projects_namedList[projects_list[[i]][[2]]] <<-
            projects_list[[i]][[1]]
        }

        ### updates project dropdown
        updateSelectInput(session, "var", choices = sort(names(projects_namedList)))

        ### update waiter loading screen once login successful
        waiter_update(html = tagList(
          img(src = "synapse_logo.png", height = "120px"),
          h3(sprintf(
            "Welcome, %s!", syn_getUserProfile()$userName
          ))
        ))
        Sys.sleep(2)
        waiter_hide()
      },
      error = function(err) {
        Sys.sleep(2)
        waiter_update(html = tagList(
          img(src = "synapse_logo.png", height = "120px"),
          h3("Looks like you're not logged in!"),
          span(
            "Please ",
            a("login", href = "https://www.synapse.org/#!LoginPlace:0", target = "_blank"),
            " to Synapse, then refresh this page."
          )
        ))
      }
    )
  })


  ###### BUTTONS STUFF  !!! remove last arrow
  Previous_Button <- tags$div(actionButton(
    "Prev_Tab",
    HTML('<div class="col-sm-4"><i class="fa fa-angle-double-left fa-2x"></i></div>')
  ))
  Next_Button <- div(actionButton(
    "Next_Tab",
    HTML('<div class="col-sm-4"><i class="fa fa-angle-double-right fa-2x"></i></div>')
  ))

  list_tabs <- c("instructions", "data", "template", "upload")

  output$Next_Previous <- renderUI({
    tab_list <- list_tabs
    if (input[["tabs"]] == "upload") {
      # column(1,offset=1,Previous_Button)
    } else if (input[["tabs"]] == "instructions") {
      column(1, offset = 10, Next_Button)
    } else {
      div(
        column(1, offset = 1, Previous_Button),
        column(1, offset = 8, Next_Button)
      )
    }
  })

  observeEvent(input$Prev_Tab, {
    tab_list <- list_tabs
    current_tab <- which(tab_list == input[["tabs"]])
    updateTabItems(session, "tabs", selected = tab_list[current_tab - 1])
  })

  observeEvent(input$Next_Tab, {
    tab_list <- list_tabs
    current_tab <- which(tab_list == input[["tabs"]])
    updateTabItems(session, "tabs", selected = tab_list[current_tab + 1])
  })

  ####### BUTTONS END

  ### lists folder datasets if exists in project
  observeEvent(
    ignoreNULL = TRUE,
    ignoreInit = TRUE,
    input$var,
    {
      output$folders <- renderUI({
        selected_project <- input$var

        # if selected_project not empty
        if (!is.null(selected_project)) {
          project_synID <-
            projects_namedList[[selected_project]] ### get synID of selected project

          ### gets folders per project
          folder_list <-
            synapse_driver$SynapseStorage$getStorageDatasetsInProject(synStore_obj, project_synID)
          folders_namedList <- c()
          for (i in seq_along(folder_list)) {
            folders_namedList[folder_list[[i]][[2]]] <- folder_list[[i]][[1]]
          }
          folderNames <- names(folders_namedList)

          ### updates foldernames
          selectInput(
            inputId = "dataset",
            label = "Folder:",
            choices = folderNames
          )
        }
      })
    }
  )

  ### mapping from display name to schema name
  schema_name <- config$manifest_schemas$schema_name
  display_name <- config$manifest_schemas$display_name

  output$manifest_display_name <- renderUI({
    selectInput(
      inputId = "template_type",
      label = "Template:",
      choices = display_name
    )
  })

  observeEvent(
    {
      input$dataset
      input$template_type
    },
    {
      sapply(
        c(
          "text_div",
          "text_div2",
          "tbl2",
          "gsheet_btn",
          "gsheet_div",
          "submitButton"
        ),
        FUN = hide
      )
    }
  )

  schema_to_display_lookup <- data.frame(schema_name, display_name)

  # loading screen for template link generation
  manifest_w <- Waiter$new(
    html = tagList(
      spin_plus(), br(),
      h4("Generating link...")
    ),
    color = "rgba(66, 72, 116, .9)"
  )

  ### shows new metadata link when get gsheets template button pressed OR updates old metadata if is exists
  observeEvent(input$download, {
    manifest_w$show()

    if (is.null(input$template_type)) {
      output$text <- renderUI({
        tags$span(
          class = "error_msg",
          HTML("Please <b>select a template</b> from the 'Select your Dataset' tab !")
        )
      })
    } else {
      selected_folder <- input$dataset
      selected_project <- input$var

      ### lookup schema template name
      template_type_df <-
        schema_to_display_lookup[match(
          input$template_type,
          schema_to_display_lookup$display_name
        ), 1, drop = F]
      template_type <- as.character(template_type_df$schema_name)

      project_synID <-
        projects_namedList[[selected_project]] ### get synID of selected project

      folder_list <-
        synapse_driver$SynapseStorage$getStorageDatasetsInProject(synStore_obj, project_synID)
      folders_namedList <- c()
      for (i in seq_along(folder_list)) {
        folders_namedList[folder_list[[i]][[2]]] <- folder_list[[i]][[1]]
      }
      folder_synID <- folders_namedList[[selected_folder]]

      ### checks if a manifest already exists
      existing_manifestID <-
        synapse_driver$SynapseStorage$getDatasetManifest(synStore_obj, folder_synID)

      ### if there isn't an existing manifest make a new one
      if (existing_manifestID == "") {
        file_list <-
          synapse_driver$SynapseStorage$getFilesInStorageDataset(synStore_obj, folder_synID)
        file_namedList <- c()
        for (i in seq_along(file_list)) {
          file_namedList[file_list[[i]][[2]]] <- file_list[[i]][[1]]
        }
        filename_list <- names(file_namedList)

        manifest_url <-
          metadata_model$getModelManifest(
            paste0(config$community, " ", input$template_type),
            template_type,
            filenames = as.list(filename_list)
          )
        ### make sure not scalar if length of list is 1 in R
        ## add in the step to convert names later ###
      } else {
        ### if the manifest already exists
        manifest_entity <- syn_get(existing_manifestID)
        # prepopulatedManifestURL = mm.populateModelManifest("test_update", entity.path, component)
        manifest_url <-
          metadata_model$populateModelManifest(
            paste0(config$community, " ", input$template_type),
            manifest_entity$path,
            template_type
          )
      }

      output$text <- renderUI({
        tags$a(href = manifest_url, manifest_url, target = "_blank") ### add link to data dictionary when we have it ###
      })
    }

    ## links shows in text box
    show("text_div")
    ### if want a progress bar need more feedback from API to know how to increment progress bar ###

    manifest_w$hide()
  })

  ### renders fileInput ui
  output$fileInput_ui <- renderUI({
    fileInput(
      "file1",
      "Upload CSV File",
      accept = c(
        "text/csv",
        "text/comma-separated-values",
        ".csv"
      )
    )
  })

  ### reads csv file and previews
  rawData <- eventReactive(ignoreNULL = FALSE, input$file1, {
    if (is.null(input$file1)) {
      return(NULL)
    } # if no file uploaded, return null
    infile <- readr::read_csv(input$file1$datapath,
      na = c("", "NA"),
      col_types = readr::cols(.default = "c")
    ) %>%
      replace(., is.na(.), "") # change NA to blank to match schema output)
    ### remove empty rows/columns where readr called it "X"[digit] for unnamed col
    infile <- infile[, !grepl("^X", colnames(infile))]
    infile <- infile[rowSums(is.na(infile)) != ncol(infile), ]
  })

  observeEvent(input$file1, {
    sapply(c(
      "text_div2",
      "tbl2",
      "gsheet_btn",
      "gsheet_div",
      "submitButton"
    ),
    FUN = hide
    )
  })

  ### renders in DT for preview
  observeEvent(rawData(), {
    output$tbl <- DT::renderDT({
      datatable(rawData(), options = list(lengthChange = FALSE, scrollX = TRUE), rownames = FALSE)
    })
  })

  ## loading screen for validating metadata
  validate_w <- Waiter$new(
    html = tagList(
      spin_plus(), br(),
      h4("Validating...")
    ),
    color = "rgba(66, 72, 116, .9)"
  )

  ### toggles validation status when validate button pressed
  observeEvent(input$validate, {
    validation_res <- NULL
    type_error <- NULL
    help_msg <- NULL

    validate_w$show()

    if (!is.null(rawData()) & !is.null(input$template_type)) {
      ### lookup schema template name
      template_type_df <- schema_to_display_lookup[match(input$template_type, schema_to_display_lookup$display_name), 1, drop = F]
      template_type <- as.character(template_type_df$schema_name)

      annotation_status <- metadata_model$validateModelManifest(input$file1$datapath, template_type)

      if (length(annotation_status) != 0) {
        validation_res <- "invalid"
        # mismatched template index
        inx_mt <- which(sapply(annotation_status, function(x) grepl("Component value provided is: .*, whereas the Template Type is: .*", x[[3]])))
        # missing column index
        inx_ws <- which(sapply(annotation_status, function(x) grepl("Wrong schema", x[[2]])))

        if (length(inx_mt) > 0) { # mismatched error(s): selected template mismatched with validating template

          waiter_msg <- "Mismatched Template Found !"
          # get all mismatched components
          error_values <- sapply(annotation_status[inx_mt], function(x) x[[4]][[1]]) %>% unique()
          column_names <- "Component"

          # error messages for mismatch
          mismatch_c <- error_values %>%
            sQuote() %>%
            paste(collapse = ", ")
          type_error <- paste0("The submitted metadata contains << <b>", mismatch_c, "</b> >> in the Component column, but requested validation for << <b>", input$template_type, "</b> >>.")
          help_msg <- paste0("Please check that you have selected the correct template in the <b>Select your Dataset</b> tab and 
                              ensure your metadata contains <b>only</b> one template, e.g. ", input$template_type, ".")

          # get wrong columns and values for updating preview table
          errorDT <- data.frame(
            Column = sapply(annotation_status[inx_mt], function(i) i[[2]]),
            Value = sapply(annotation_status[inx_mt], function(i) i[[4]][[1]])
          )
        } else if (length(inx_ws) > 0) { # wrong schema error(s): validating metadata miss any required columns

          waiter_msg <- "Wrong Schema Used !"
          type_error <- "The submitted metadata does not contain all required column(s)."
          help_msg <- "Please check that you used the correct template in the <b>'Get Metadata Template'</b> tab and
                       ensure your metadata contains all required columns."
        } else {
          waiter_msg <- sprintf("%d errors found", length(annotation_status))
          type_error <- paste0("The submitted metadata have ", length(annotation_status), " errors.")
          help_msg <- NULL

          errorDT <- data.frame(
            Column = sapply(annotation_status, function(i) i[[2]]),
            Value = sapply(annotation_status, function(i) i[[4]][[1]]),
            Error = sapply(annotation_status, function(i) i[[3]])
          )
          # sort rows based on input column names
          errorDT <- errorDT[order(match(errorDT$Column, colnames(rawData()))), ]

          # output error messages as data table
          show("tbl2")
          output$tbl2 <- DT::renderDT({
            datatable(errorDT,
              caption = "The errors are also highlighted in the preview table above.",
              rownames = FALSE, options = list(
                pageLength = 50, scrollX = TRUE,
                scrollY = min(50 * length(annotation_status), 400),
                lengthChange = FALSE, info = FALSE, searching = FALSE
              )
            )
          })
        }

        validate_w$update(
          html = h3(waiter_msg)
        )

        ### update DT view with incorrect values
        ### currently only one column, requires backend support of multiple
        output$tbl <- DT::renderDT({
          if (length(inx_ws) > 0) {
            # if it is wrong schema error, highlight all cells
            datatable(rawData(), options = list(lengthChange = FALSE, scrollX = TRUE)) %>%
              formatStyle(1, target = "row", backgroundColor = "yellow")
          } else {
            datatable(rawData(), options = list(lengthChange = FALSE, scrollX = TRUE)) %>%
              formatStyle(errorDT$Column,
                backgroundColor = styleEqual(errorDT$Value, rep("yellow", length(errorDT$Value)))
              )
          }
        })

        show("gsheet_btn")
      } else {
        validation_res <- "valid"
        ### show submit button
        output$submit <- renderUI({
          actionButton("submitButton", "Submit to Synapse")
        })
      }
    }

    ### format output text
    output$text2 <- renderUI({
      text_class <- ifelse(!is.null(validation_res) && validation_res == "valid", "success_msg", "error_msg")

      tagList(
        if (is.null(input$template_type)) span(class = text_class, HTML("Please <b>select a template</b> from the 'Select your Dataset' tab !<br><br>")),
        if (is.null(rawData())) span(class = text_class, HTML("Please <b>upload</b> a filled template !")),
        if (!is.null(validation_res)) span(class = text_class, HTML(paste0("Your metadata is <b>", validation_res, "</b> !!!"))),
        if (!is.null(type_error)) span(class = text_class, HTML(paste0("<br><br>", type_error))),
        if (!is.null(help_msg)) span(class = text_class, HTML(paste0("<br><br>", help_msg)))
      )
    })

    show("text_div2")

    Sys.sleep(2.5)

    validate_w$hide()
  })

  # if user click gsheet_btn, generating gsheet
  observeEvent(input$gsheet_btn, {
    # loading screen for Google link generation
    gsheet_w <- Waiter$new(
      html = tagList(
        spin_plus(), br(),
        h4("Generating link...")
      ),
      color = "rgba(66, 72, 116, .9)"
    )

    gsheet_w$show()

    ### lookup schema template name
    template_type_df <-
      schema_to_display_lookup[match(
        input$template_type,
        schema_to_display_lookup$display_name
      ), 1, drop = F]
    template_type <- as.character(template_type_df$schema_name)

    ## if error not empty aka there is an error
    filled_manifest <-
      metadata_model$populateModelManifest(
        paste0(config$community, " ", input$template_type),
        input$file1$datapath,
        template_type
      )

    show("gsheet_div")

    output$gsheet_link <- renderUI({
      # tags$a(href = filled_manifest, filled_manifest, target = "_blank")
      HTML(
        paste0(
          '<a target="_blank" href="',
          filled_manifest,
          '">Edit on the Google Sheet.</a>'
        )
      )
    })

    hide("gsheet_btn") # hide btn once link generated

    gsheet_w$hide()
  })

  ## loading screen for submitting data
  submit_w <- Waiter$new(
    html = tagList(
      img(src = "loading.gif"),
      h4("Submitting...")
    ),
    color = "#424874"
  )

  ### submit button
  observeEvent(input$submitButton, {
    submit_w$show()

    ### reads in csv
    infile <-
      readr::read_csv(input$file1$datapath, na = c("", "NA"))

    ### remove empty rows/columns where readr called it "X"[digit] for unnamed col
    infile <- infile[, !grepl("^X", colnames(infile))]
    infile <- infile[rowSums(is.na(infile)) != ncol(infile), ]

    ### IF an assay component selected (define assay components)
    ## note for future - the type to filter (eg assay) on could probably also be a config choice
    assay_schemas <-
      config$manifest_schemas$display_name[config$manifest_schemas$type == "assay"]

    ### and adds entityID, saves it as synapse_storage_manifest.csv, then associates with synapse files
    if (input$template_type %in% assay_schemas) {
      ### make into a csv or table for assay components
      ### already has entityId
      if ("entityId" %in% colnames(infile)) {
        write.csv(
          infile,
          file = "./files/synapse_storage_manifest.csv",
          quote = TRUE,
          row.names = FALSE,
          na = ""
        )
      } else {
        # if not get ids
        selected_folder <- input$dataset
        selected_project <- input$var

        project_synID <-
          projects_namedList[[selected_project]] ### get synID of selected project
        folder_list <-
          synapse_driver$SynapseStorage$getStorageDatasetsInProject(synStore_obj, project_synID)
        folders_namedList <- c()
        for (i in seq_along(folder_list)) {
          folders_namedList[folder_list[[i]][[2]]] <- folder_list[[i]][[1]]
        }

        folder_synID <- folders_namedList[[selected_folder]]

        file_list <-
          synapse_driver$SynapseStorage$getFilesInStorageDataset(synStore_obj, folder_synID)
        file_namedList <- c()
        for (i in seq_along(file_list)) {
          file_namedList[file_list[[i]][[2]]] <- file_list[[i]][[1]]
        }

        files_df <- stack(file_namedList)
        colnames(files_df) <- c("entityId", "Filename")
        files_entity <-
          inner_join(infile, files_df, by = "Filename")

        write.csv(
          files_entity,
          file = "./files/synapse_storage_manifest.csv",
          quote = TRUE,
          row.names = FALSE,
          na = ""
        )
      }
      selected_project <- input$var
      selected_folder <- input$dataset

      project_synID <-
        projects_namedList[[selected_project]] ### get synID of selected project

      folder_list <-
        synapse_driver$SynapseStorage$getStorageDatasetsInProject(synStore_obj, project_synID)
      folders_namedList <- c()
      for (i in seq_along(folder_list)) {
        folders_namedList[folder_list[[i]][[2]]] <- folder_list[[i]][[1]]
      }
      folder_synID <- folders_namedList[[selected_folder]]

      ### associates metadata with data and returns manifest id
      manifest_id <-
        synapse_driver$SynapseStorage$associateMetadataWithFiles(
          synStore_obj,
          "./files/synapse_storage_manifest.csv",
          folder_synID
        )
      print(manifest_id)
      manifest_path <-
        paste0("synapse.org/#!Synapse:", manifest_id)
      ### if no error
      if (startsWith(manifest_id, "syn") == TRUE) {
        nx_report_success(
          "Success!",
          paste0("Manifest submitted to: ", manifest_path)
        )
        rm("./files/synapse_storage_manifest.csv")

        ### clear inputs
        output$text2 <- renderUI({
          HTML("")
        })
        output$submit <- renderUI({

        })

        ### rerenders fileinput UI
        output$fileInput_ui <- renderUI({
          fileInput(
            "file1",
            "Upload CSV File",
            accept = c(
              "text/csv",
              "text/comma-separated-values",
              ".csv"
            )
          )
        })
        ### renders empty df
        output$tbl <- DT::renderDT(datatable(as.data.frame(matrix(
          0,
          ncol = 0, nrow = 0
        ))))
      } else {
        submit_w$update(html = tagList(
          img(src = "synapse_logo.png", height = "115px"),
          h3("Uh oh, looks like something went wrong!"),
          span(manifest_id, " is not a valid Synapse ID. Try again?")
        ))
        rm("/tmp/synapse_storage_manifest.csv")
      }
    } else {
      ## if not assay type tempalte
      write.csv(
        infile,
        file = "./files/synapse_storage_manifest.csv",
        quote = TRUE,
        row.names = FALSE,
        na = ""
      )

      selected_project <- input$var
      selected_folder <- input$dataset

      project_synID <-
        projects_namedList[[selected_project]] ### get synID of selected project
      # folder_synID <- get_folder_synID(synStore_obj, project_synID, selected_folder)

      folder_list <-
        synapse_driver$SynapseStorage$getStorageDatasetsInProject(synStore_obj, project_synID)
      folders_namedList <- c()
      for (i in seq_along(folder_list)) {
        folders_namedList[folder_list[[i]][[2]]] <- folder_list[[i]][[1]]
      }
      folder_synID <- folders_namedList[[selected_folder]]

      ### associates metadata with data and returns manifest id
      manifest_id <-
        synapse_driver$SynapseStorage$associateMetadataWithFiles(
          synStore_obj,
          "./files/synapse_storage_manifest.csv",
          folder_synID
        )
      print(manifest_id)
      manifest_path <-
        paste0("synapse.org/#!Synapse:", manifest_id)

      ### if uploaded provided valid synID message
      if (startsWith(manifest_id, "syn") == TRUE) {
        nx_report_success(
          "Success!",
          paste0("Manifest submitted to: ", manifest_path)
        )
        rm("./files/synapse_storage_manifest.csv")

        ### clear inputs
        output$text2 <- renderUI({
          HTML("")
        })
        output$submit <- renderUI({

        })

        ### rerenders fileinput UI
        output$fileInput_ui <- renderUI({
          fileInput(
            "file1",
            "Upload CSV File",
            accept = c(
              "text/csv",
              "text/comma-separated-values",
              ".csv"
            )
          )
        })
        ### renders empty df
        output$tbl <- DT::renderDT(datatable(as.data.frame(matrix(
          0,
          ncol = 0, nrow = 0
        ))))
      } else {
        submit_w$update(html = tagList(
          img(src = "synapse_logo.png", height = "115px"),
          h3("Uh oh, looks like something went wrong!"),
          span(manifest_id, " is not a valid Synapse ID. Try again?")
        ))
        rm("/tmp/synapse_storage_manifest.csv")
      }
    }
    Sys.sleep(3)
    submit_w$hide()
  })
})