# Calculating GEP of Water Provisioning Services for Agriculture

This repository contains code used to calculate the Global Ecosystem Product (GEP) of water provisioning services for agriculture.

# Code Files

All code files are stored directly in the `Code` folder. The scripts cover data preparation, calculation of water-contribution coefficients, and GEP calculation.

## `0-functions-dataprep.R`

Contains helper functions used to calculate crop water requirements, allocate CropGBWater water consumption to crop-growth stages, calculate water-satisfaction ratios, and derive water-contribution coefficients.

## `1-1-prep-Ky-Kc-table.qmd`

Creates the crop parameter table by matching CropGBWater crop classes to FAO/CROPWAT crop classes and compiling crop coefficients (`Kc`) and yield-response factors (`Ky`).

**Main output:** `CropGBWater_FAO_Ky_Kc.csv`

## `1-2-ET0-daily-compile.qmd`

Processes CropGBWater daily reference evapotranspiration (`ET0`) data for 2018–2022 and creates a 365-day, five-year average daily ET0 profile for each `ClimateID`.

**Main output:** `et0_daily_avg_2020.csv`

## `1-3-prep-spam.qmd`

Processes SPAM 2020 data to calculate rainfed and irrigated crop production quantities and production shares for each CropGBWater crop and country.

**Main output:** `spam_cropgbwater_share.csv`

## `1-4-prep-FAO-GPV-table.qmd`

Processes FAOSTAT Gross Production Value (GPV) data and uses SPAM production shares to estimate rainfed and irrigated GPV for each CropGBWater crop and country.

**Main output:** `GPV_rainfed_irrigated_CropGBWater_2020.csv`

## `2-1-CropGBWater-Wheat.qmd`

Processes the CropGBWater wheat data by matching wheat crop-calendar information to water-consumption data and separating spring wheat, winter wheat, and full-cover winter wheat.

**Main outputs:**  
`Wheat_spring_grid_avg.csv`  
`Wheat_winter_grid_avg.csv`  
`Wheat_winter_fullcover_grid_avg.csv`

## `2-2-CropGBWater-process.qmd`

Processes the remaining CropGBWater crops by merging crop-calendar information with the gridded water-consumption data for each crop.

**Main outputs:** crop-specific files saved as `<CropGBWater_crop>_grid_avg.csv`

## `2-3-VMR-CropGBWater-grid.qmd`

Processes the Vegetation Moisture Recycling (VMR) data and assigns the precipitation-side VMR share to each CropGBWater grid cell based on its geographic location.

**Main output:** `CropGBWater_grid_code_vmr.csv`

## `3-irr-rain-lambda.qmd`

Calculates crop- and country-specific water-contribution coefficients (`lambda`) for rainfed green water, irrigated green water, blue irrigation water, and total irrigation water. It also calculates VMR-origin green-water contribution coefficients for rainfed and irrigated production.

**Main output:** `lambda_jr_tbl_CropGBWater.csv`

## `4-GVA-share.qmd`

Calculates country-level agricultural value-added shares (`theta`) from agricultural value added and gross output, with imputation for countries with missing values.

**Main output:** `theta_table_final.csv`

## `5-GEP-ag-rain-irr.qmd`

Calculates crop- and country-level GEP of water provisioning services for agriculture using the water-contribution coefficients, agricultural value-added shares, and rainfed and irrigated GPV. It also calculates VMR-associated green-water GEP for rainfed and irrigated production.

**Main outputs:**  
`gep_agwater_crop_country_source.csv`  
`gep_agwater_country_source.csv`  
`wateruse_ag_gep.csv`