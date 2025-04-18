#' 
#' @author Abigail Lewis. Updated by ABP 26 April 2024, ASL 30 April 2024, ABP 07 Jan 2025 and 26 Jan 25
#' @title flag_seasonal_csvs
#' @description This function loads the saved CTD csv from this year (or multiple years) and adds data flags
#' 
#' @param ctd_season_csvs directory of CTD seasonal csvs
#' @param intermediate_file_name file name of un-flagged dataset
#' @param output_file_name file name of flagged dataset
#' @param historical_files if TRUE, add in the files from 2013-2017 to the data file
#' @param CTD_FOLDER high level CTD folder where L1 output will be stored
#'
#' @return no output
#'

flag_seasonal_csvs <- function(ctd_season_csvs = "../CTD_season_csvs",
                               intermediate_file_name = "ctd_L0.csv",
                               output_file_name = "ctd_L1.csv",
                               historical_files = F, 
                               CTD_FOLDER = "../",
                               maintenance_file = "https://raw.githubusercontent.com/CareyLabVT/Reservoirs/master/Data/DataNotYetUploadedToEDI/Raw_CTD/CTD_Maintenance_Log.csv"){
  
  
  intermediate_file_name = "ctd_L0.csv"
  
  ctd1 <- read.csv(paste0(ctd_season_csvs, "/", intermediate_file_name)) #Load saved data
  
 #ctd1 <- read.csv("Data/DataNotYetUploadedToEDI/Raw_CTD/CTD_season_csvs/ctd_L0_2018-2024.csv")
  
  ctd = ctd1 %>%
    mutate(
      DateTime = as.POSIXct(DateTime, format = "%Y-%m-%dT%H:%M:%SZ"),
           Reservoir = ifelse(Reservoir == "BRV", "BVR", Reservoir), #Fix typo
           Reservoir = sub("_", "", Reservoir), #Remove underscore
           Reservoir = as.factor(Reservoir))
  
  # convert everything to EDT so we can fix times later
  
  ctd$DateTime <- force_tz(ctd$DateTime, tzone = "Etc/GMT+4")
 
  
  #Flag codes
  #0=Not suspect, 
  #1=Sample not taken, 
  #2=Instrument malfunction, 
  #3=Sample below detection,
  #4=Negative value set to 0 or NA
  #5=No sensor on CTD,
  #6=Measurement above water (removed for most vars)
  #7=Datetime missing time (date is meaningful but not time)
  #8=Measurement outside of expected range but retained in dataset
  
  # get the column names. Make it dynamic so if columns change
  
  flag_cols <- ctd%>%
    select(-c(Flag, Reservoir, Site, SN, Depth_m))%>%
    colnames()
  
  # create vectors for different qaqc:
  
  # Flag Change negative to 0 
  neg <- flag_cols[!grepl("DateTime|Temp_C|ORP_mV|DescRate_ms", flag_cols)]
  
  # Change negative to 0
  zero <- flag_cols[grepl("PAR_umolm2s|Turbidity_NTU|Chla_ugL|DO_mgL|DOsat_percent", flag_cols)]
  
  # Change negative to NA
  changed_Na <- neg[!grepl("PAR_umolm2s|Turbidity_NTU|Chla_ugL|DO_mgL|DOsat_percent", neg)]
  
  # Flag cols not in 7809
  
  only_new <- c("CDOM_ugL", "Phycoerythrin_ugL",
                "Phycocyanin_ugL")
  
  # Flag cols not in 8188
  only_old <- c("pH","ORP_mV")
  
  
  # variables that changed to NA when CTD out of the water
  water_vars <- c("Chla_ugL","Turbidity_NTU","Cond_uScm","SpCond_uScm","DO_mgL",
                  "DOsat_percent","pH","ORP_mV", "CDOM_ugL", "Phycoerythrin_ugL",
                  "Phycocyanin_ugL")
  
  
  # Make the Flag columns and flag a few things
  for(j in flag_cols) {
    
    #for loop to create new columns in data frame
    #creates flag column + name of variable
    ctd[,paste0("Flag_",j)] <- 0
    
    # puts in flag 5 if the sensor was not the 7809 CTD
    ctd[c(which(is.na(ctd[,j]) & ctd[,"SN"] ==7809 & (j %in% only_new))), paste0("Flag_",j)]<-5
    
    # puts in flag 5 if the sensor was not the 8188 CTD
    ctd[c(which(is.na(ctd[,j]) & ctd[,"SN"] ==8188 & (j %in% only_old))), paste0("Flag_",j)]<-5
    
    # puts in flag 2 if value not collected
    ctd[c(which(is.na(ctd[,j]) & paste0("Flag_",j)==0)),paste0("Flag_",j)] <- 2
  }
  
  ## Take out the negative conductivity spike in casts
  # Make an array of the rows that have a negative conductivity, which indicates a spike
  
  row <- which(ctd$Cond_uScm<0,arr.ind = TRUE)

  if(length(row) != 0) {
  
  if(length(row) != 0){
  
  # Make a blank array
  gfg <- NULL
  
  # make a new list of observations that are not in sequential order this gives us each of the spikes
  for(i in 1:length(row)){
    # if the previous observation in the list is greater than 1 or it is the first in the list add it to the spike list
    if(abs(row[i]-row[i-1])>1|| i==1){
      
      # add to the list
      gfg <- append(gfg, row[i]) 
    }
    
  }
  
  # Loop through that list of rows that just created
  for(d in 1:length(gfg)){
    
    # Get the sequence of rows in the low spike which we want to remove  
    low <- as.numeric(gfg[d])-6
    high <- as.numeric(gfg[d])+22
    
    # change those rows in Conductivity and specific conductance to NA
    ctd[c(low:high), c("Cond_uScm", "SpCond_uScm")] <- NA
    
    # Then flag those columns that we change
    
    ctd[c(low:high), c("Flag_Cond_uScm", "Flag_SpCond_uScm")] <- 4
    
   }
  }
  
  # Now back to flagging more things. 
  for(j in flag_cols[!grepl("DateTime", flag_cols)]){
    
    # Flag values less than 0 with a flag 4 except: Temp, ORP and Decent rate
    ctd[c(which(!is.na(ctd[,j]) & ctd[,j]<0 & (j %in% neg))), paste0("Flag_",j)]<-4
    
    # change negative values to 0
    ctd[c(which(!is.na(ctd[,j]) & ctd[,j]<0 & (j %in% zero))),j]<-0
    
    # change negative values to NA
    ctd[c(which(!is.na(ctd[,j]) & ctd[,j]<0 & (j %in% changed_Na))),j]<-NA
    
    #Not all variables are meaningful out of the water
    ctd[c(which(!is.na(ctd[,j]) & ctd$Depth_m<0 & (j %in% water_vars))), paste0("Flag_",j)] <- 6
    ctd[c(which(ctd$Depth_m<0 & (j %in% water_vars))), j]<-NA
   
    
  }  
  
  
  # Fix times
  # CTD times in June 2024 are incorrect by ~3 hr after the CTD came back from the spa
  ctd[ctd$DateTime>as.Date("2024-06-01") &
                ctd$DateTime<as.Date("2024-06-21") & ctd$SN == 8188, "DateTime"] = 
    ctd[ctd$DateTime>as.Date("2024-06-01") &
                  ctd$DateTime<as.Date("2024-06-21") & ctd$SN == 8188, "DateTime"] + 60*60*3 #to align with actual date of cast
  
  
  # CTD times in 2022 are incorrect by ~3 hr
  ctd$DateTime[ctd$DateTime>as.Date("2021-12-01") &
                         ctd$DateTime<as.Date("2023-03-01")] = 
    ctd$DateTime[ctd$DateTime>as.Date("2021-12-01") &
                           ctd$DateTime<as.Date("2023-03-01")] + lubridate::hours(3) #to align with published data
  
  # CTD times in 2020 and 2021 are incorrect by ~13 hr
  ctd$DateTime[ctd$DateTime > as.Date("2020-01-01") & 
                         ctd$DateTime < as.Date("2021-08-02")] = 
    ctd$DateTime[ctd$DateTime > as.Date("2020-01-01") & 
                           ctd$DateTime < as.Date("2021-08-02")] + lubridate::hours(13) #to align with published data
  
  # fix a month in 2023 after the old CTD came back 
  ctd[ctd$DateTime>as.Date("2023-07-03") &
                ctd$DateTime<as.Date("2023-08-01") & ctd$SN == 7809, "DateTime"] = 
    ctd[ctd$DateTime>as.Date("2023-08-01") &
                  ctd$DateTime<as.Date("2023-07-03") & ctd$SN == 7809, "DateTime"] + 60*60*4
  
  # CTD times in 2018 are incorrect by ~4 hr
  ctd$DateTime[lubridate::year(ctd$DateTime) == 2018] = 
    ctd$DateTime[lubridate::year(ctd$DateTime) == 2018] - lubridate::hours(4) #to align with published data
  
  # final = ctd%>%
  #   mutate(DateTime = as.POSIXct(DateTime, format = "%Y-%m-%d %H:%M:%S"))
  # 
  
  # convert to time to America/New_York with daylight savings observed
  
  ctd$DateTime <- with_tz(ctd$DateTime, tz = "America/New_York")
  
  # Double check the all the times
  
  
  # Add in historical files
  if(historical_files==T){
    
    # Read the files from before 2018 and add them to the current file
    # NOTE: I THINK we do NOT want to change this link in future revisions, given our decision in 2024 to 
    # Re-process all casts 2018-present rather than pulling the most recent data on EDI
    # NOTE: With the new EDI protocols, we might need to change this link. 
    ctd_edi <- read_csv("https://pasta.lternet.edu/package/data/eml/edi/200/13/27ceda6bc7fdec2e7d79a6e4fe16ffdf")
    
    # Force time to New York with daylight savings observed to merge with the current file
      ctd_edi$DateTime <- force_tz(ctd_edi$DateTime, tzone = "America/New_York")
    
    #Add SN to historical EDI data
    ctd_edi <- ctd_edi %>%
      filter(year(DateTime)<2018) %>% #only want casts before 2018
      mutate(SN = ifelse(year(DateTime) %in% c(2013:2016), 4397, 7809))
    
    # bind historical and current
    
    ctd <- ctd_edi %>%
      mutate(Flag_CDOM_ugL = ifelse(SN %in% c(4397,7809), 5, Flag_CDOM_ugL),
             Flag_Phycoerythrin_ugL = ifelse(SN %in% c(4397,7809), 5, Flag_Phycoerythrin_ugL),
             Flag_Phycocyanin_ugL = ifelse(SN %in% c(4397,7809), 5, Flag_Phycocyanin_ugL)) %>%
      filter(!DateTime %in% ctd$DateTime) %>% #Remove files that have been re-processed
      filter(!DateTime == "2021-12-14 10:45:36") %>% #This file was re-processed and the time was updated
      full_join(ctd)
    
  }

  # fix the time and flag it 
  ctd_flagged = ctd %>% 
    select(-Flag)%>%
    mutate(
      #DateTime 
      Flag_DateTime = ifelse(lubridate::hour(DateTime)==12&
                               lubridate::minute(DateTime)==0&
                               lubridate::seconds(DateTime)==0,
                             7,0)) #Flag times that are missing time (date is meaningful but not time)
  
 
  
  #Fix for CTD when conductivity and specific conductivity columns were switched
  #spec_Cond_uScm=Cond_uScm/(1+(0.02*(Temp_C-25)))) so if temp is less than 25 conductivity is
  # less than specific conductivity and if temp is greater than 25 then conductivity is greater than 
  # specific conductivity. Based on this I created the a CTD_check column if the columns were good or bad. 
  # If they were bad then the conductivity and the spec. conductivity column need to be flipped. 
  
  #ABP 10 DEC 21
  
  CTD_fix=ctd_flagged%>%
    add_column(CTD_check = NA)%>% #create the CTD_check column
    #sets up criteria for the CTD_check column either "good","bad" or "NA"(if no data)
    mutate(
      CTD_check=ifelse(Temp_C<25& Cond_uScm<SpCond_uScm & !is.na(SpCond_uScm), "good", CTD_check),
      CTD_check=ifelse(Temp_C<25& Cond_uScm>SpCond_uScm & !is.na(SpCond_uScm), "bad", CTD_check),
      CTD_check=ifelse(Temp_C>25& Cond_uScm>SpCond_uScm & !is.na(SpCond_uScm), "good", CTD_check),
      CTD_check=ifelse(Temp_C>25& Cond_uScm<SpCond_uScm & !is.na(SpCond_uScm), "bad", CTD_check),
      CTD_check=ifelse(is.na(SpCond_uScm), "good",CTD_check),
      CTD_check=ifelse(Cond_uScm==0, "bad", CTD_check))%>%
    #the next part switches the column if labeled "bad" in CTD_check 
    transform(., SpCond_uScm = ifelse(CTD_check == 'bad' & !is.na(SpCond_uScm), Cond_uScm, SpCond_uScm), 
              Cond_uScm = ifelse(CTD_check == 'bad' & !is.na(SpCond_uScm), SpCond_uScm, Cond_uScm))%>%
    select(-CTD_check)%>%
    mutate(Site=ifelse(Reservoir=="BVR"&Site==1,40,Site),
           Site=ifelse(Site==49,50,Site))
    
  
  #Order columns
  CTD_fix_renamed = CTD_fix%>% 
    select(any_of(c("Reservoir", "Site", "SN", "DateTime", "Depth_m", "Temp_C", "DO_mgL", "DOsat_percent", 
                    "Cond_uScm", "SpCond_uScm", "Chla_ugL", "Turbidity_NTU", "pH", "ORP_mV", "PAR_umolm2s", 
                    "CDOM_ugL", "Phycoerythrin_ugL", "Phycocyanin_ugL", "DescRate_ms", 
                    "Flag_DateTime", "Flag_Temp_C", "Flag_DO_mgL", "Flag_DOsat_percent", 
                    "Flag_Cond_uScm", "Flag_SpCond_uScm", "Flag_Chla_ugL", "Flag_Turbidity_NTU", 
                    "Flag_pH", "Flag_ORP_mV", "Flag_PAR_umolm2s", "Flag_CDOM_ugL", 
                    "Flag_Phycoerythrin_ugL", "Flag_Phycocyanin_ugL", "Flag_DescRate_ms")))
  
  # order the DateTime on the CTD casts
  CTD_fix_renamed <- CTD_fix_renamed[order(CTD_fix_renamed$DateTime),]
  
  print(maintenance_file)
  
  # ## ADD MAINTENANCE LOG FLAGS 
  # The maintenance log includes manual edits to the data for suspect samples or human error
  log_read <- read_csv(maintenance_file, col_types = cols(
    .default = col_character(),
    TIMESTAMP_start = col_datetime("%Y-%m-%d %H:%M:%S%*"),
    TIMESTAMP_end = col_datetime("%Y-%m-%d %H:%M:%S%*"),
    flag = col_integer()
  ))
  
  # filter out the maintenance log 
  log <- log_read%>%
    filter(TIMESTAMP_start>CTD_fix_renamed[1,"DateTime"]|is.na(TIMESTAMP_start))
  
  for(i in 1:nrow(log)){
    if (!is.na(log$Depth[i])) {
      warning("Maintenance log specifies a depth, but code is not set up to deal with specified depths")
    }
    
    ### Assign variables based on lines in the maintenance log.
    
    ### get start and end time of one maintenance event
    start <- force_tz(as.POSIXct(log$TIMESTAMP_start[i]), tzone = "America/New_York")
    end <- force_tz(as.POSIXct(log$TIMESTAMP_end[i]), tzone = "America/New_York")
    
    ### Get the Reservoir Name
    Reservoir <- log$Reservoir[i]
    # NAs mean fix everything
    if(is.na(Reservoir)){Reservoir <- unique(CTD_fix_renamed$Reservoir)}
    
    ### Get the Site Number
    Site <- as.numeric(log$Site[i])
    # NAs mean fix everything
    if(is.na(Site)){Site <- unique(CTD_fix_renamed$Site)}
    
    ### Get the SN
    SN <- as.numeric(log$SN[i])
    # NAs mean fix everything
    if(is.na(SN)){SN <- unique(CTD_fix_renamed$SN)}
    
    ### Get the Maintenance Flag
    flag <- log$flag[i]
    
    ### Get the correct columns
    
    colname_start <- ifelse(log$start_parameter[i]%in%colnames(CTD_fix_renamed)==F,NA, log$start_parameter[i])
    colname_end <- ifelse(log$end_parameter[i]%in%colnames(CTD_fix_renamed)==F,NA, log$end_parameter[i])
    
    
    ### if it is only one parameter then only one column will be selected
    
    if(is.na(colname_start) | is.na(colname_end)){ 
      if(is.na(colname_start) & !is.na(colname_end)){
        maintenance_cols <- colnames(CTD_fix_renamed%>%select(colname_end))
      }else if(is.na(colname_end) & !is.na(colname_start)){
        maintenance_cols <- colnames(CTD_fix_renamed%>%select(colname_start))
        
      }else{
        # if columns aren't in the data frame
        maintenance_cols <- NA
      }
    }else{
      maintenance_cols <- colnames(CTD_fix_renamed%>%select(colname_start:colname_end))
    }
    
    ### Get the DateTimes
    if(is.na(start) & is.na(end)){
      Time <- CTD_fix_renamed |> select(DateTime)
    }else if(is.na(end)){
      # If there the maintenance is on going then the columns will be removed until
      # an end date is added
      Time <- CTD_fix_renamed |> filter(DateTime >= start) |> select(DateTime)
    }else if (is.na(start)){
      # If there is only an end date change columns from beginning of data frame until end date
      Time <- CTD_fix_renamed |> filter(DateTime <= end) |> select(DateTime)
    }else {
      Time <- CTD_fix_renamed |> filter(DateTime >= start & DateTime <= end) |> select(DateTime)
    }
    times <- unique(Time$DateTime)
    
    ### This is where information in the maintenance log gets updated
    
    #Flag codes
    #0=Not suspect, 
    #1=Sample not taken, 
    #2=Instrument malfunction, 
    #3=Sample below detection,
    #4=Negative value set to 0 or NA
    #5=No sensor on CTD,
    #6=Measurement above water (removed for most vars)
    #7=Datetime missing time (date is meaningful but not time)
    #8=Measurement outside of expected range but retained in dataset
    
    if(is.na(maintenance_cols)[1]==T){
      print("No maintenance_cols selected")
    }else{
      
      if(flag %in% c(2, 5)){ ## UPDATE THIS WITH ANY NEW FLAGS
        # UPDATE THE MANUAL ISSUE FLAGS (BAD SAMPLE / USER ERROR) AND SET TO NEW VALUE
        if(is.na(log$update_value[i]) || !log$update_value[i] == "NO CHANGE"){
          CTD_fix_renamed[CTD_fix_renamed$DateTime %in% times &
                            CTD_fix_renamed$Reservoir %in% Reservoir &
                            CTD_fix_renamed$Site %in% Site &
                            CTD_fix_renamed$SN %in% SN,
                          maintenance_cols] <- as.numeric(log$update_value[i])
        }
        CTD_fix_renamed[CTD_fix_renamed$DateTime %in% times &
                          CTD_fix_renamed$Reservoir %in% Reservoir &
                          CTD_fix_renamed$Site %in% Site &
                          CTD_fix_renamed$SN %in% SN, 
                        paste0("Flag_",maintenance_cols)] <- flag
        
      } else if (flag %in% c(8)){
        # value is suspect
        CTD_fix_renamed[CTD_fix_renamed$DateTime %in% times, paste0("Flag_",maintenance_cols)] <- flag
        
      }else{
        warning("Flag not coded in the L1 script. See Austin or Adrienne")
      }
    }  
  } # end for loop
  
  ### Filter out high Turbidity and PAR values
  
  CTD_fix_renamed <- CTD_fix_renamed|>
  mutate(
    #remove and flag excessively high turbidity
    Flag_Turbidity_NTU = ifelse(!is.na(Turbidity_NTU) & Turbidity_NTU > 200, 2, Flag_Turbidity_NTU),
    Turbidity_NTU = ifelse(!is.na(Turbidity_NTU) & Turbidity_NTU > 200, NA, Turbidity_NTU),
    
    #remove and flag excessively high PAR
    Flag_PAR_umolm2s = ifelse(!is.na(PAR_umolm2s) & PAR_umolm2s > 3000, 2, Flag_PAR_umolm2s),
    PAR_umolm2s = ifelse(!is.na(PAR_umolm2s) & PAR_umolm2s > 3000, NA, PAR_umolm2s)
  )
 
  # Check if there are any casts that were duplicated
  
  dup <- nrow(CTD_fix_renamed[duplicated(CTD_fix_renamed),])
  
  
  # Dups after 2017 are from NAs for maintenance and the CTD depth and temp are the same
  
  if(dup > 0){
    warning(paste0("There were ", dup, " rows that were duplicated and will be removed"))
  }
  # Remove any duplicates 
  CTD_fix_renamed2 <- CTD_fix_renamed[!duplicated(CTD_fix_renamed),]
  
  write.csv(CTD_fix_renamed2, paste0(CTD_FOLDER, output_file_name), row.names = FALSE)
  message(paste0("Successfully updated ", output_file_name))
  
  return(CTD_fix_renamed)
}

