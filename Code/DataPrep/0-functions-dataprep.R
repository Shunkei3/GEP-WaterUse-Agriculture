# /*===========================================*/
#'= Step 1: month-stage ETm calculation  =
# /*===========================================*/
get_etm_month_stage <- function(wc_dt, et0_dt){
  #/*--------------------------------*/
  #' ## Test Run
  # wc_dt <- wc_dt_crop_i
  # et0_dt <- et0_daily_dt
  #/*--------------------------------*/
  
  wc_dt <- copy(wc_dt)
  et0_dt <- copy(et0_dt)

  #/*--------------------------------*/
  #' ## Required columns
  #/*--------------------------------*/
  req_wc_cols <- c(
    "ClimateID", "grid_code",
    "Kc_ini", "Kc_mid", "Kc_end",
    "L_ini", "L_dev", "L_mid", "L_late",
    "J_plant", "Totalperiod"
  )
  
  req_et0_cols <- c("ClimateID", "doy", "ET0")
  
  stopifnot(all(req_wc_cols %in% names(wc_dt)))
  stopifnot(all(req_et0_cols %in% names(et0_dt)))

  # Check ET0 table
  if (et0_dt[, anyDuplicated(.SD), .SDcols = c("ClimateID", "doy")] > 0) {
    stop("et0_dt has duplicated ClimateID-doy rows.")
  }

  #/*--------------------------------*/
  #' ## Keep rows with valid crop calendar
  #/*--------------------------------*/
  wc_dt <- wc_dt[
    ClimateID != -9999 &
      !is.na(J_plant) &
      !is.na(Totalperiod)
  ]

  # Integerize calendar variables
  int_cols <- c("L_ini", "L_dev", "L_mid", "L_late", "J_plant", "Totalperiod")
  wc_dt[, (int_cols) := lapply(.SD, function(x) as.integer(round(x))), .SDcols = int_cols]

  # Numericize Kc variables
  kc_cols <- c("Kc_ini", "Kc_mid", "Kc_end")
  wc_dt[, (kc_cols) := lapply(.SD, as.numeric), .SDcols = kc_cols]

  #/*--------------------------------*/
  #' ## Keep unique calendar combinations first
  #/*--------------------------------*/
  # This avoids expanding every grid cell to daily rows unnecessarily.
  cal_cols <- c(
    "ClimateID",
    "Kc_ini", "Kc_mid", "Kc_end",
    "L_ini", "L_dev", "L_mid", "L_late",
    "J_plant", "Totalperiod"
  )

  cal_dt <- unique(wc_dt[, ..cal_cols])
  cal_dt[, cal_id := .I]

  # Indicator for crop seasons that cross calendar years
  cal_dt[, harvest_raw_doy := J_plant + Totalperiod - 1L]
  cal_dt[, crosses_multiple_years := harvest_raw_doy > 365L]

  #/*--------------------------------*/
  #' ## Expand each unique calendar to daily crop-cycle records
  #/*--------------------------------*/
  # dap: day after planting, starting from 0
  daily_dt <- cal_dt[,
    .(dap = seq.int(0L, Totalperiod - 1L)),
    by = .(
      cal_id, ClimateID,
      Kc_ini, Kc_mid, Kc_end,
      L_ini, L_dev, L_mid, L_late,
      J_plant, Totalperiod,
      harvest_raw_doy, crosses_multiple_years
    )
  ]

  # Raw crop-cycle day and wrapped day of year
  daily_dt[, raw_doy := J_plant + dap]
  daily_dt[, crop_year_offset := as.integer((raw_doy - 1L) %/% 365L)]
  daily_dt[, doy := ((raw_doy - 1L) %% 365L) + 1L]

  # Month lookup for 365-day representative calendar
  doy_month_dt <- 
    data.table(
      doy = 1:365,
      month = as.integer(format(as.Date("2001-01-01") + 0:364, "%m")),
      month_name = month.abb[as.integer(format(as.Date("2001-01-01") + 0:364, "%m"))]
    )
  
  daily_dt <- 
    merge(
      daily_dt,
      doy_month_dt,
      by = "doy",
      all.x = TRUE
    )
  
  #/*--------------------------------*/
  #' ## Stage assignment
  #/*--------------------------------*/
  daily_dt[
    ,
    stage := fcase(
      dap < L_ini, "ini",
      dap < L_ini + L_dev, "dev",
      dap < L_ini + L_dev + L_mid, "mid",
      default = "late"
    )
  ]
  
  daily_dt[
    ,
    stage_day := fcase(
      stage == "ini", as.integer(dap + 1L),
      stage == "dev", as.integer(dap - L_ini + 1L),
      stage == "mid", as.integer(dap - L_ini - L_dev + 1L),
      stage == "late", as.integer(dap - L_ini - L_dev - L_mid + 1L),
      default = NA_integer_
    )
  ]

  #/*--------------------------------*/
  #' ## Daily Kc calculation
  #/*--------------------------------*/
  # Initial and mid are constant.
  # Development and late stages are linearly interpolated.
  daily_dt[
    ,
    Kc := fcase(
      stage == "ini",
      as.numeric(Kc_ini),

      stage == "dev" & L_dev > 0,
      as.numeric(Kc_ini + (Kc_mid - Kc_ini) * stage_day / L_dev),

      stage == "mid",
      as.numeric(Kc_mid),

      stage == "late" & L_late > 0,
      as.numeric(Kc_mid + (Kc_end - Kc_mid) * stage_day / L_late),

      default = NA_real_
    )
  ]
  
  #/*--------------------------------*/
  #' ## Merge daily ET0 by ClimateID and doy
  #/*--------------------------------*/
  # Important:
  # et0_dt is a representative 365-day ET0 profile by ClimateID-doy.
  # Therefore, cross-year crop days are merged using wrapped doy.
  daily_dt <- 
    merge(
      daily_dt,
      et0_dt[, .(ClimateID, doy, ET0)],
      by = c("ClimateID", "doy"),
      all.x = TRUE
    )

  # Daily ETm in mm/day
  daily_dt[, ETm := ET0 * Kc]

  #/*--------------------------------*/
  #' ## Aggregate to calendar-month-stage
  #/*--------------------------------*/
  # Note that different stages can occur in the same month.
  # For cross-year crops, crop_year_offset identifies whether the day belongs
  # to the next crop year under the wrapped 365-day representative calendar.
  etm_cal_dt <- daily_dt[,
    .(
      ETm_mm = sum(ETm, na.rm = TRUE),
      n_days = .N,
      n_missing_ET0 = sum(is.na(ET0)),
      n_days_next_year = sum(crop_year_offset > 0L)
    ),
    by = .(
      cal_id,
      ClimateID,
      month,
      month_name,
      stage,
      crosses_multiple_years
    )
  ]

  #/*--------------------------------*/
  #' ## Attach cal_id back to each grid cell
  #/*--------------------------------*/
  wc_cal_dt <- 
    merge(
      wc_dt[, c("grid_code", cal_cols), with = FALSE],
      cal_dt,
      by = cal_cols,
      all.x = TRUE
    )
  
  #/*--------------------------------*/
  #' ## Attach grid_code to month-stage ETm
  #/*--------------------------------*/
  out_dt <- 
    merge(
      wc_cal_dt[
        ,
        .(
          grid_code,
          ClimateID,
          cal_id,
          crosses_multiple_years
        )
      ],
      etm_cal_dt,
      by = c("cal_id", "ClimateID", "crosses_multiple_years"),
      all.x = TRUE,
      allow.cartesian = TRUE
    )
  
  setorder(out_dt, grid_code, month, stage)

  return(out_dt[])
}



# /*===========================================*/
#'=  Step 2: Allocate WC to month-stage =
# /*===========================================*/
get_wc_month_stage <- function(wc_dt, etm_month_stage_dt){
  #/*--------------------------------*/
  #' ## Test Run
  # wc_dt <- wc_dt_crop_i
  # etm_month_stage_dt <- etm_month_stage
  #/*--------------------------------*/

  wc_dt <- copy(wc_dt)
  etm_month_stage_dt <- copy(etm_month_stage_dt)

  month_names <- month.abb

  #/*--------------------------------*/
  #' ## Identify crop-area columns
  #/*--------------------------------*/
  # Based on Data_S5 README:
  # XXXX_A = total crop area in ha
  # XXXX_I = irrigated crop area in ha
  # XXXX_R = rainfed crop area in ha
  area_cols <- grep("_(A|I|R)$", names(wc_dt), value = TRUE)

  if (length(area_cols) == 0) {
    stop("No crop-area columns ending in _A, _I, or _R were found in wc_dt.")
  }

  id_cols <- c("ADM0_NAME", "FIPS0", "grid_code", "ClimateID", area_cols)

  # Helper function to reshape monthly CropGBWater columns
  melt_wc_var <- function(dt, var_pattern, out_name){

    cols <- grep(
      paste0("_", var_pattern, "_(", paste(month_names, collapse = "|"), ")$"),
      names(dt),
      value = TRUE
    )
    
    if (length(cols) == 0) {
      stop("No columns found for: ", var_pattern)
    }

    # Water-consumption columns should be numeric.
    # Explicitly convert them to double before melt to avoid integer/double coercion warnings.
    dt[, (cols) := lapply(.SD, as.numeric), .SDcols = cols]
    
    out <- melt(
      dt,
      id.vars = id_cols,
      measure.vars = cols,
      variable.name = "var_month",
      value.name = out_name
    )
    
    out[
      ,
      month_name := sub(
        paste0(".*_(", paste(month_names, collapse = "|"), ")$"),
        "\\1",
        var_month
      )
    ]
    
    out[, month := match(month_name, month_names)]
    out[, var_month := NULL]
    
    return(out[])
  }

  #/*--------------------------------*/
  #' ## Reshape monthly water-consumption variables
  #/*--------------------------------*/
  wc_gn_rf_dt <- melt_wc_var(wc_dt, "cwu_gn_rf", "WC_gn_rf_mm")
  wc_gn_ir_dt <- melt_wc_var(wc_dt, "cwu_gn_ir", "WC_gn_ir_mm")
  wc_bl_dt    <- melt_wc_var(wc_dt, "cwu_bl",    "WC_bl_mm")

  # Combine the three separate long-format wc tables into one monthly table
  merge_cols <- c(id_cols, "month", "month_name")

  wc_month_dt <- Reduce(
    function(x, y) {
      merge(
        x, y,
        by = merge_cols,
        all = TRUE
      )
    },
    list(wc_gn_rf_dt, wc_gn_ir_dt, wc_bl_dt)
  )

  #/*--------------------------------*/
  #' ## Calculate stage allocation weights
  #/*--------------------------------*/
  # Using stage- and month-specific ETm, calculate the stage allocation weights
  # for each stage-month pair. Use this weight to allocate monthly water
  # consumption to each stage.
  etm_month_stage_dt[,
    ETm_month_mm := sum(ETm_mm, na.rm = TRUE),
    by = .(grid_code, ClimateID, month)
  ][, 
    alpha_stage := fifelse(
      ETm_month_mm > 0,
      ETm_mm / ETm_month_mm,
      NA_real_
    )
  ]

  #' NOTE:
  #' ETm_mm: crop water requirement for a specific grid-month-stage combination
  #' ETm_month_mm: total crop water requirement for that grid-month, summed across stages
  #' alpha_stage: share of monthly ETm allocated to that stage

  #/*--------------------------------*/
  #' ## Merge ETm allocation weights with monthly water consumption
  #/*--------------------------------*/
  out_dt <- merge(
    etm_month_stage_dt,
    wc_month_dt,
    by = c("grid_code", "ClimateID", "month", "month_name"),
    all.x = TRUE
  )
  
  #/*--------------------------------*/
  #' ## Allocate monthly water consumption to stages
  #/*--------------------------------*/
  out_dt[,
    `:=`(
      WC_gn_rf_stage_mm = WC_gn_rf_mm * alpha_stage,
      WC_gn_ir_stage_mm = WC_gn_ir_mm * alpha_stage,
      WC_bl_stage_mm    = WC_bl_mm * alpha_stage
    )
  ]

  setorder(out_dt, grid_code, month, stage)
  
  return(out_dt[])
}




# /*===========================================*/
#'= Step 3: Convert convert stage-level values from mm to m3 using crop-specific harvested area.
# /*===========================================*/

get_wc_stage_volume <- function(wc_month_stage_dt){
  #/*--------------------------------*/
  #' ## Test Run
  # wc_month_stage_dt <- wc_month_stage
  #/*--------------------------------*/
  
  dt <- copy(wc_month_stage_dt)

  #/*--------------------------------*/
  #' ## Find area columns
  #/*--------------------------------*/
  # Based on Data_S5 README:
  # XXXX_I = irrigated area in ha
  # XXXX_R = rainfed area in ha
  area_irr_col <- grep("_I$", names(dt), value = TRUE)
  area_rf_col  <- grep("_R$", names(dt), value = TRUE)

  if (length(area_irr_col) != 1) {
    stop("Could not uniquely identify irrigated area column ending in _I.")
  }

  if (length(area_rf_col) != 1) {
    stop("Could not uniquely identify rainfed area column ending in _R.")
  }

  # Standardize area column names
  setnames(dt, area_irr_col, "area_irr_ha")
  setnames(dt, area_rf_col,  "area_rf_ha")

  #/*--------------------------------*/
  #' ## Required columns
  #/*--------------------------------*/
  req_cols <- c(
    "ETm_mm",
    "WC_gn_rf_stage_mm",
    "WC_gn_ir_stage_mm",
    "WC_bl_stage_mm",
    "area_rf_ha",
    "area_irr_ha"
  )

  stopifnot(all(req_cols %in% names(dt)))

  #/*--------------------------------*/
  #' ## Convert mm to m3
  #/*--------------------------------*/
  # 1 mm over 1 ha = 10 m3
  dt[
    ,
    `:=`(
      ETm_rf_stage_m3   = ETm_mm * area_rf_ha * 10,
      ETm_ir_stage_m3   = ETm_mm * area_irr_ha * 10,

      WC_gn_rf_stage_m3 = WC_gn_rf_stage_mm * area_rf_ha * 10,
      WC_gn_ir_stage_m3 = WC_gn_ir_stage_mm * area_irr_ha * 10,
      WC_bl_stage_m3    = WC_bl_stage_mm * area_irr_ha * 10
    )
  ]

  return(dt[])
}


# /*===========================================*/
#'=  Step 5: s_jrgh calculation =
# /*===========================================*/
# For each (j, r, g, m, h), calculate s (i.e., water satisfaction ratio)

get_s_jrgh <- function(wc_stage_volume){
  #/*--------------------------------*/
  #' ## Test Run
  # wc_stage_volume <- wc_stage_volume
  #/*--------------------------------*/
  
  dt <- copy(wc_stage_volume)
  
  #/*--------------------------------*/
  #' ## Required columns
  #/*--------------------------------*/
  req_cols <- c(
    "ETm_rf_jrgh_m3",
    "ETm_ir_jrgh_m3",
    "WC_gn_rf_jrgh_m3",
    "WC_gn_ir_jrgh_m3",
    "WC_bl_jrgh_m3"
  )
  
  stopifnot(all(req_cols %in% names(dt)))
  
  #/*--------------------------------*/
  #' ## Satisfied water volumes
  #/*--------------------------------*/
  #' Rainfed green water
  dt[,
    Sat_gn_rf_jrgh_m3 := pmin(
      WC_gn_rf_jrgh_m3,
      ETm_rf_jrgh_m3
    )
  ]
  
  #' Green water on irrigated land
  dt[,
    Sat_gn_ir_jrgh_m3 := pmin(
      WC_gn_ir_jrgh_m3,
      ETm_ir_jrgh_m3
    )
  ]
  
  #' Blue irrigation water
  #' This is the incremental water requirement satisfied by blue water
  #' after green water on irrigated land has already contributed.
  dt[,
    Sat_bl_ir_jrgh_m3 :=
      pmin(WC_gn_ir_jrgh_m3 + WC_bl_jrgh_m3, ETm_ir_jrgh_m3) -
      pmin(WC_gn_ir_jrgh_m3, ETm_ir_jrgh_m3)
  ]
  
  #' Total water satisfaction on irrigated land
  dt[,
    Sat_total_ir_jrgh_m3 := pmin(
      WC_gn_ir_jrgh_m3 + WC_bl_jrgh_m3,
      ETm_ir_jrgh_m3
    )
  ]
  
  #/*--------------------------------*/
  #' ## Water satisfaction ratios
  #/*--------------------------------*/
  dt[,
    s_gn_rf_jrgh := fifelse(
      ETm_rf_jrgh_m3 > 0,
      Sat_gn_rf_jrgh_m3 / ETm_rf_jrgh_m3,
      NA_real_
    )
  ]
  
  dt[,
    s_gn_ir_jrgh := fifelse(
      ETm_ir_jrgh_m3 > 0,
      Sat_gn_ir_jrgh_m3 / ETm_ir_jrgh_m3,
      NA_real_
    )
  ]
  
  dt[,
    s_bl_ir_jrgh := fifelse(
      ETm_ir_jrgh_m3 > 0,
      Sat_bl_ir_jrgh_m3 / ETm_ir_jrgh_m3,
      NA_real_
    )
  ]
  
  dt[,
    s_total_ir_jrgh := fifelse(
      ETm_ir_jrgh_m3 > 0,
      Sat_total_ir_jrgh_m3 / ETm_ir_jrgh_m3,
      NA_real_
    )
  ]
  
  #/*--------------------------------*/
  #' ## Diagnostic check
  #/*--------------------------------*/
  #' s_gn_ir_jrgh + s_bl_ir_jrgh should equal s_total_ir_jrgh
  dt[,
    s_total_ir_check := s_gn_ir_jrgh + s_bl_ir_jrgh
  ]
  
  setorder(dt, ADM0_NAME, grid_code, stage)
  
  return(dt[])
}


#/*===========================================*/
#'= Step 6: Calculate s_jrh = =
#/*===========================================*/
#' Aggregate the numerator and denominator volumes first, then calculate s_jrh

get_s_jrh <- function(s_jrgh_tbl){
  #/*--------------------------------*/
  #' ## Test Run
  # s_jrgh_tbl <- s_jrgh_tbl
  #/*--------------------------------*/
  
  dt <- copy(s_jrgh_tbl)
  
  #/*--------------------------------*/
  #' ## Aggregate satisfied volumes and ETm volumes
  #/*--------------------------------*/
  s_jrh_tbl <- dt[
    ,
    .(
      ETm_rf_jrh_m3 = sum(ETm_rf_jrgh_m3, na.rm = TRUE),
      ETm_ir_jrh_m3 = sum(ETm_ir_jrgh_m3, na.rm = TRUE),
      
      Sat_gn_rf_jrh_m3 = sum(Sat_gn_rf_jrgh_m3, na.rm = TRUE),
      Sat_gn_ir_jrh_m3 = sum(Sat_gn_ir_jrgh_m3, na.rm = TRUE),
      Sat_bl_ir_jrh_m3 = sum(Sat_bl_ir_jrgh_m3, na.rm = TRUE),
      Sat_total_ir_jrh_m3 = sum(Sat_total_ir_jrgh_m3, na.rm = TRUE),
      
      n_grid = uniqueN(grid_code)
    ),
    by = .(
      ADM0_NAME,
      stage
    )
  ]
  
  #/*--------------------------------*/
  #' ## Calculate country-crop-stage water satisfaction ratios
  #/*--------------------------------*/
  s_jrh_tbl[,
    s_gn_rf_jrh := fifelse(
      ETm_rf_jrh_m3 > 0,
      Sat_gn_rf_jrh_m3 / ETm_rf_jrh_m3,
      NA_real_
    )
  ]
  
  s_jrh_tbl[,
    s_gn_ir_jrh := fifelse(
      ETm_ir_jrh_m3 > 0,
      Sat_gn_ir_jrh_m3 / ETm_ir_jrh_m3,
      NA_real_
    )
  ]
  
  s_jrh_tbl[,
    s_bl_ir_jrh := fifelse(
      ETm_ir_jrh_m3 > 0,
      Sat_bl_ir_jrh_m3 / ETm_ir_jrh_m3,
      NA_real_
    )
  ]
  
  s_jrh_tbl[,
    s_total_ir_jrh := fifelse(
      ETm_ir_jrh_m3 > 0,
      Sat_total_ir_jrh_m3 / ETm_ir_jrh_m3,
      NA_real_
    )
  ]
  
  setorder(s_jrh_tbl, ADM0_NAME, stage)
  
  return(s_jrh_tbl[])
}


# /*===========================================*/
#'=  lambda calculation: Helper function =
# /*===========================================*/
  calc_lambda <- function(s, Ky){
    ok <- !is.na(s) & !is.na(Ky)

    if (!any(ok)) {
      return(NA_real_)
    }

    sum(Ky[ok] * s[ok]) / sum(Ky[ok])
  }
