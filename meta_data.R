## Modified : 20210417

#### Creates Meatadata YML file and updates if needed, then converts yml file to
#### XML

#remotes::install_github("eco4cast/neon4cast")

library(neon4cast)

forecast_file <- paste0("phenology-", Sys.Date(),"-VT_Ph_GDD.csv")
metadata_yaml <- paste0("phenology-metadata-VT_Ph_GDD.yml")
forecast_id <- paste0("phenology-", Sys.Date(), "-VT_Ph_GDD")

neon4cast::write_metadata_eml(forecast_file = forecast_file,
                              metadata_yaml = metadata_yaml,
                              forecast_issue_time = Sys.Date(),
                              forecast_iteration_id = forecast_id)

