## package BioSIM not available on CRAN nor GitHub; needs to be installed as follows:
## install.packages("https://sourceforge.net/projects/repiceasource/files/latest", repos = NULL,  type = "source")
## install.packages("https://sourceforge.net/projects/biosimclient.mrnfforesttools.p/files/latest", repos = NULL,  type = "source")

defineModule(sim, list(
  name = "canWind",
  description = "Simulate mean annual wind speeds/directions based on climate/weather projections in BioSIM.",
  keywords = c("BioSIM", "ClimaticWind_Annual"),
  authors = c(
    person(c("Alex", "M"), "Chubaty", email = "achubaty@for-cast.ca", role = c("aut", "cre")),
    person(c("Eliot", "JB"), "McIntire", email = "eliot.mcintire@canada.ca", role = c("aut"))
  ),
  childModules = character(0),
  version = numeric_version("0.0.2"),
  spatialExtent = raster::extent(rep(NA_real_, 4)),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list("citation.bib"),
  documentation = list("README.md", "canWind.Rmd"),
  reqdPkgs = list(
    "BioSIM", ## not on CRAN/GitHub; see install info at top of this file
    "PredictiveEcology/LandR@LCC2010 (>= 1.0.4)",
    "magrittr",
    "PredictiveEcology/mpbutils (>= 0.1.2)",
    "raster", "reproducible", "sf", "sp"
  ),
  parameters = rbind(
    defineParameter("aggFact", "integer", 40L, NA_character_, NA_character_,
                    "Aggregation/diaggregation factor to use to rescale wind maps (i.e., to use coarser resolution)."),
    defineParameter("climateModel", "character", "GCM4", NA_character_, NA_character_,
                    "The climate model to use. One of 'GCM4' or 'RCM4'"),
    defineParameter("climateScenario", "character", "RCP45", NA_character_, NA_character_,
                    "The climate scenario to use. One of 'RCP45' or 'RCP85'."),
    defineParameter(".plots", "character", "", NA_character_, NA_character_,
                    "TODO: description needed"),
    defineParameter(".plotInitialTime", "numeric", start(sim), 1981, 2100,
                    "This describes the simulation time at which the first plot event should occur"),
    defineParameter(".plotInterval", "numeric", NA, NA, NA,
                    "This describes the simulation time interval between plot events"),
    defineParameter(".saveInitialTime", "numeric", NA, NA, NA, "This describes the simulation time at which the first save event should occur"),
    defineParameter(".saveInterval", "numeric", NA, NA, NA, "This describes the simulation time interval between save events"),
    defineParameter(".tempdir", "character", NULL, NA, NA,
                    "Temporary (scratch) directory to use for transient files (e.g., GIS intermediates)."),
    defineParameter(".useCache", "logical", FALSE, NA, NA,
                    "Should this entire module be run with caching activated?"),
    defineParameter("years", "numeric", 1981:2100, NA, NA,
                    "sequence of years to get wind data/projections for.")
  ),
  inputObjects = bindrows(
    expectsInput("rasterToMatch", "RasterLayer",
                 desc = "if not supplied, will default to standAgeMap",
                 sourceURL = NA),
    expectsInput("standAgeMap", "RasterLayer",
                 desc = "stand age map in study area, default is Canada national stand age map",
                 sourceURL = paste0("http://ftp.maps.canada.ca/pub/nrcan_rncan/Forests_Foret/",
                                    "canada-forests-attributes_attributs-forests-canada/",
                                    "2001-attributes_attributs-2001/",
                                    "NFI_MODIS250m_2001_kNN_Structure_Stand_Age_v1.tif")),
    expectsInput("studyArea", "SpatialPolygons",
                 desc = "The study area to which all maps will be cropped and reprojected.",
                 sourceURL = NA)
  ),
  outputObjects = bindrows(
    createsOutput(objectName = "windMaps", objectClass = "RasterStack",
                  desc = "Raster maps corresponding to wind speed and direction.")
  )
))

## event types
#   - type `init` is required for initialiazation

doEvent.canWind <- function(sim, eventTime, eventType, debug = FALSE) {
  switch(eventType,
    "init" = {
      # do stuff for this event
      sim <- Init(sim)

      # schedule future event(s)
      sim <- scheduleEvent(sim, P(sim)$.plotInitialTime, "canWind", "plot")
    },
    "plot" = {
      # ! ----- EDIT BELOW ----- ! #
      # do stuff for this event
      Plot(sim$windMaps)

      # schedule future event(s)
      sim <- scheduleEvent(sim, time(sim) + P(sim)$.plotInterval, "canWind", "plot")

      # ! ----- STOP EDITING ----- ! #
    },
    warning(paste("Undefined event type: '", current(sim)[1, "eventType", with = FALSE],
                  "' in module '", current(sim)[1, "moduleName", with = FALSE], "'", sep = ""))
  )
  return(invisible(sim))
}

.inputObjects <- function(sim) {
  cacheTags <- c(currentModule(sim), "function:.inputObjects")
  cPath <- cachePath(sim)
  dPath <- asPath(getOption("reproducible.destinationPath", dataPath(sim)), 1)
  if (getOption("LandR.verbose", TRUE) > 0)
    message(currentModule(sim), ": using dataPath '", dPath, "'.")

  #mod$prj <- paste("+proj=aea +lat_1=47.5 +lat_2=54.5 +lat_0=0 +lon_0=-113",
  #                 "+x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs +ellps=GRS80 +towgs84=0,0,0")
  mod$prj <- paste("+proj=lcc +lat_1=49 +lat_2=77 +lat_0=0 +lon_0=-95",
                   "+x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs")

  if (!suppliedElsewhere("studyArea")) {
    ## TODO: use more general default studyArea
    sim$studyArea <- mpbStudyArea(ecoregions = c(112, 120, 122, 124, 126), mod$prj,
                                  cPath, dPath) %>%
      as_Spatial(.)
  }

  if (!suppliedElsewhere("standAgeMap", sim)) {
    sim$standAgeMap <- LandR::prepInputsStandAgeMap(
      startTime = 2010,
      ageUrl = na.omit(extractURL("standAgeMap")),
      destinationPath = dPath,
      studyArea = sim$studyArea,
      userTags = c("stable", currentModule(sim))
    )
    sim$standAgeMap[] <- asInteger(sim$standAgeMap[])
  }

  if (!suppliedElsewhere("rasterToMatch", sim)) {
    sim$rasterToMatch <- sim$standAgeMap
  }

  if (!suppliedElsewhere("windMaps")) {
    aggFact <- P(sim)$aggFact

    ## make coarser
    aggRTM <- raster::raster(sim$rasterToMatch)
    aggRTM <- raster::aggregate(aggRTM, fact = aggFact)
    aggRTM <- LandR::aggregateRasByDT(sim$rasterToMatch, aggRTM, fn = mean)

    dem <- Cache(prepInputsCanDEM,
                 studyArea = sim$studyArea,
                 rasterToMatch = aggRTM,
                 destinationPath = inputPath(sim))

    windStk <- LandR::BioSIM_getWind(
      dem = dem,
      years = P(sim)$years,
      climModel = P(sim)$climateModel,
      rcp = P(sim)$climateScenario
    )

    ## Visualize
    Plots(windStk)

    windMaps <- disaggregate(windStk, fact = aggFact)
    sim$windMaps <- raster::stack(crop(windMaps, sim$rasterToMatch))  ## TODO: speed and dir??

    if (!compareRaster(sim$windMaps, sim$rasterToMatch, stopiffalse = FALSE)) {
      warning("wind raster is not same resolution as sim$rasterToMatch; please debug")
      browser() ## TODO: remove
    }
  }

  # ! ----- STOP EDITING ----- ! #
  return(invisible(sim))
}

Init <- function(sim) {
  # # ! ----- EDIT BELOW ----- ! #

  # ! ----- STOP EDITING ----- ! #
  return(invisible(sim))
}
