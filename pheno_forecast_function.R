

#### function to fit nimble model to historical data at all NEON phenology sites and forecast phenology at all sites using post-predictive function outside of nimble

pheno_forecast <- function(data, ## REQUIRED cols: time, siteID, gcc_90, gcc_sd, doy, daily_min, daily_max
                           forecast_start_date,
                           forecast_end_date,
                           Tbase=10){ # default is 10 but can be changed if specified in the function call
  
  library(tidyverse)
  library(nimble)
  library(tidybayes)
  library(lubridate)
  
  data1 <- data
  
  # Calculate driver variable, cumulative GDD, from daily min and max temps
  data <- data %>% mutate(GDD_day = ((daily_max + daily_min)/2) - Tbase) %>% 
    mutate(GDD_day = ifelse(GDD_day > 0, GDD_day, 0)) %>% 
    mutate(year = year(time)) %>% 
    group_by(siteID, year) %>% 
    mutate(GDD = cumsum(GDD_day)) %>% 
    filter(doy < 180)
  
  # separate out training and forecast time periods
  train <- data[data$time < forecast_start_date, ]
  train <- na.omit(train)
  forecast <- data[data$time > forecast_start_date, ] # Defines forecast dataframe from NOAA to be used 
  # later on in function
  
  #ggplot(data = data, aes(x = doy, y = GDD)) +
  #  geom_point(aes(color = as.factor(year))) +
  #  facet_wrap(~siteID)
  
  ### DEFINE NIMBLE MODEL
  logistic <- nimbleCode({
    ## Priors
    theta1 ~ dnorm(0, sd = 10000)
    theta2 ~ dnorm(0, sd = 10000)
    theta3 <- -50
    theta4 ~ dnorm(0, sd = 10000)
    sd_data ~ dunif(0.00001, 100)
    
    # Loop through data points
    for(i in 1:n){
      ## Process model
      pred[i] <- theta1 + theta2 * exp(theta3 + theta4 * x[i]) / (1 + exp(theta3 + theta4 * x[i])) 
      ## Data model
      y[i]  ~ dnorm(pred[i], sd = sd_data)
    }
  })
  
  ### Define Constants and Data
  constants <- list(n = length(train$gcc_90))
  data <- list(x = train$GDD,
               y = train$gcc_90)
  
  ### Initialize Chains
  nchain <- 3
  inits <- list()
  for(i in 1:nchain){
    inits[[i]] <- list(theta1 = rnorm(1, 0.34, 0.05), 
                       theta2 = rnorm(1, 0.11, 0.05),
                       theta4 = rnorm(1, 0.4, 0.05),
                       sd_data = runif(1, 0.05, 0.15 ))
  }
  
  ### Runs NIMBLE model
  nimble.out <- nimbleMCMC(code = logistic,
                           data = data,
                           inits = inits,
                           constants = constants,
                           monitors = c("theta1", 
                                        "theta2",
                                        "theta4", 
                                        "sd_data"),
                           niter = 10000,
                           nchains = 3,
                           samplesAsCodaMCMC = TRUE)
  
  ### Set Burn Value and burn start of chains
  burnin <- 1000                               
  nimble.burn <- window(nimble.out, start=burnin)
  
  ### Analyitics
  traceplot(nimble.burn) 
  gelman.diag(nimble.burn)  ## determine convergence
  
  ### Sample Chain
  chain <- nimble.burn %>%
    tidybayes::spread_draws(theta1, theta2, theta4, sd_data)
  
  pred_function <- function(x, theta1, theta2, theta3, theta4){
    theta1 + theta2 * exp(theta3 + theta4 * x) / (1 + exp(theta3 + theta4 * x))
  }
  num_samples <- 1000
  
  ## Data setup
  new <- forecast # Sets up data based on the forecasted needs for graphing purposes
  x_new <- forecast$GDD # Defines driver variables
  pred_posterior_mean <- matrix(NA, num_samples, length(x_new))   # storage for all simulations, blank matrix
  y_posterior <- matrix(NA, num_samples, length(x_new)) # Sets up empty y posterior for each run
  
  ### Runs model on sampled chain values for x values that need to be forecast
  for(i in 1:num_samples){
    sample_index <- sample(x = 1:nrow(chain), size = 1, replace = TRUE)
    pred_posterior_mean[i, ] <-pred_function(x_new, 
                                             theta1 = chain$theta1[sample_index],
                                             theta2 = chain$theta2[sample_index],
                                             theta3 = -50,
                                             theta4 = chain$theta4[sample_index])
    y_posterior[i, ] <- rnorm(length(x_new), pred_posterior_mean[i, ], sd = chain$sd_data[sample_index])
  }
  
  ### Calculates confidence in values
  conf_int <- apply(y_posterior, 2, quantile, c(0.025, 0.5, 0.975), na.rm = TRUE) # process error
  pred_mean <- apply(y_posterior, 2, mean, na.rm = TRUE) # Predicts mean
  pred_sd <- apply(y_posterior, 2, sd, na.rm = TRUE) # calculates sd of prediction
  obs_conf_int <- apply(pred_posterior_mean, 2, quantile, c(0.025, 0.5, 0.975), na.rm = TRUE) # observation error
  
  
  out <- tibble(time = new$time,            
                siteID = new$siteID,
                obs_flag = 2, # not sure what this is for currently
                mean = pred_mean,
                sd = pred_sd,
                ## Don't need CI for challenge but it is nice for graph.
                Conf_interv_02.5 = conf_int[1, ], #+ obs_conf_int[1, ], 
                Conf_interv_97.5 = conf_int[3, ], #+ obs_conf_int[3, ],
                forecast = 1,
                data_assimilation = 0,
                x = x_new,
                obs = new$gcc_90,
                doy = new$doy)
  
  
  #prediction_plot <- ggplot(out, aes(x = doy, y = mean)) +
  #  geom_ribbon(aes(ymin = Conf_interv_02.5, ymax = Conf_interv_97.5), fill = "lightblue", alpha = 0.5) +
  #  geom_line() +
  #  facet_wrap(~siteID) +
  #  geom_point(aes(y = obs), color = "gray", alpha = 0.3) +
  #  labs(y = "Phenology GCC Logistic model")
  df.p <- data1
  df.p <- df.p[df.p$year == year(Sys.Date()),]
  out.3 <- out[c("siteID", "mean", "sd", "Conf_interv_02.5", "Conf_interv_97.5", "forecast", "doy")]
  names(out.3)[names(out.3) == 'forecast'] <- 'fc'
  
  df.p$mean <- df.p$gcc_90
  df.p$sd <- df.p$gcc_sd
  df.p$Conf_interv_02.5 <- NA
  df.p$Conf_interv_97.5 <- NA
  df.p$fc <- 0
  df.p2 <- df.p[c("siteID", "mean", "sd", "Conf_interv_02.5", "Conf_interv_97.5", "fc", "doy")]
  
  plot.df <- rbind(df.p2, out.3)
  
  plot.df$fc <- as.character(plot.df$fc)
  plot.df$fc[plot.df$fc == "0"] <- "Observed"
  plot.df$fc[plot.df$fc == "1"] <- "Forecast"
  
  plot.df$fc <- as.factor(plot.df$fc)
  plot.df$date <- as.Date(plot.df$doy, origin = "2020-12-31")
  
  p1 <- ggplot(data = plot.df, aes(x = date, y = mean, color = fc)) +
    geom_ribbon(aes(ymin = Conf_interv_02.5, ymax = Conf_interv_97.5), fill = "lightblue", alpha = 0.5) +
    geom_line() +
    facet_wrap(~siteID) +
    geom_point(aes(y = mean)) +
    labs(y = "Mean Green Chromatic Coordinate (90th Percentile)", x = "Date")
  
  prediction_plot <- p1 + theme(legend.title = element_blank())
  print(prediction_plot)
  
  # Generates neat output file and writes a .csv file for the output
  out.2 <- out %>% 
    pivot_longer(mean:sd, 
                 names_to = "statistic",
                 values_to = "gcc_90") %>% 
    select(time, siteID, obs_flag, forecast, data_assimilation, statistic, gcc_90)
  
  write.csv(out.2, paste0('phenology-', Sys.Date(), '-VT_Ph_GDD', '.csv'))
  
  #### ------------------------------------END OF FUNCTION---------------------------------------####
}

