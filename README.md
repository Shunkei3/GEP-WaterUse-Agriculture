# GEP of Water Provisioning for Crop Agriculture

This repository calculates the gross ecosystem product (GEP) of water provisioning for crop agriculture. It estimates the contributions of green water on rainfed and irrigated cropland, blue water on irrigated cropland, and the vegetation moisture recycling (VMR) component of green water.

The monetary base is **commercial-agriculture GEP by country and crop**, rather than gross production value adjusted by an agricultural value-added share. The water-contribution coefficients allocate that commercial GEP to the water services. The code does not apply a separate value-added factor (`theta`) in the final calculation.

## Inputs and units

The commercial-agriculture input is `Data/Raw/CommercialAgriculture/crop_gep_2020_by_country_crop.csv`, with GEP in current 2020 US dollars. The FAOSTAT-to-CropGBWater crop mapping is `Data/Processed/CropGBWater_FAOSTAT_GPV_crop_correspondence.csv`. The code also uses CropGBWater, FAO/CROPWAT crop parameters, SPAM 2020 production, VMR, and the country correspondence in `Data/Raw/boundary/z_ee_r250_correspondence.gpkg`.

The commercial-agriculture input is converted to **thousands of current 2020 US dollars** during preparation. The final crop and country result tables are in **thousands of 2019 US dollars**: the valuation script multiplies monetary values by `255.657 / 258.811`, the ratio of the [2019 and 2020 annual-average U.S. CPI-U values](https://www.bls.gov/regions/mid-atlantic/data/consumerpriceindexannualandsemiannual_table.htm). The submission file reports country totals in **2019 US dollars**, rather than thousands of dollars.

## Code files

All scripts are in `Code/`. Several scripts refer to a local absolute path in `raw_data_dir`; set that path to your own `Data/Raw` directory before running them. The R project at the repository root provides a convenient starting point for scripts that use `here()`.

### Data preparation

`0-functions-dataprep.R` contains functions for crop water requirements, growth-stage water use, satisfaction ratios, and water-contribution coefficients.

`1-1-prep-Ky-Kc-table.qmd` matches selected CropGBWater crop classes with FAO/CROPWAT crop parameters. Its output is `Data/Processed/CropGBWater_FAO_Ky_Kc.csv`.

`1-2-ET0-daily-compile.qmd` compiles a five-year average daily reference evapotranspiration profile by climate ID. Its output is `Data/Processed/CropGBWater/et0_daily_avg_2020.csv`.

`2-1-CropGBWater-Wheat.qmd` prepares separate spring wheat, winter wheat, and full-cover winter wheat water-consumption files in `Data/Processed/CropGBWater/wc/`. Run it before `1-3-prep-spam.qmd`, which reads these wheat files.

`2-2-CropGBWater-process.qmd` prepares the other selected crops' water-consumption and crop-calendar files in `Data/Processed/CropGBWater/wc/`.

`2-3-VMR-CropGBWater-grid.qmd` assigns the VMR precipitation share to CropGBWater grid cells. Its output is `Data/Processed/CropGBWater_grid_code_vmr.csv`.

`1-3-prep-spam.qmd` prepares country-by-crop rainfed and irrigated production quantities and shares from SPAM 2020. Its output is `Data/Processed/spam_cropgbwater_share.csv`.

`1-4-prep-FAO-GPV-table.qmd` prepares rainfed and irrigated FAOSTAT gross production values as `Data/Processed/GPV_rainfed_irrigated_CropGBWater_2020.csv`. **This GPV output is not used as the monetary base in the current GEP calculation.** The script reads the crop correspondence table named above; it does not create that table.

### Coefficients and valuation

`3-irr-rain-lambda.qmd` calculates country-by-crop water-contribution coefficients (`lambda`) for rainfed green water, irrigated green water, blue water, and VMR-associated green water. It reads the prepared crop parameters, ET0, gridded crop water data, and VMR data. Its output is `Data/Processed/lambda_jr_tbl_CropGBWater.csv`.

`4-prep-commercial-GEP.qmd` matches the commercial-agriculture GEP input to CropGBWater crops using the correspondence table. For shared FAOSTAT items such as wheat and millet, it allocates the item value among CropGBWater crop classes using SPAM production. It then splits each country-by-crop GEP value between rainfed and irrigated production using SPAM production shares. Its output is `Data/Processed/commercial_gep_rainfed_irrigated_CropGBWater_2020.csv`. Missing commercial GEP inputs and undefined production shares remain missing.

`5-GEP-ag-commercial-base.qmd` combines the prepared commercial GEP with `lambda` to calculate country-by-crop GEP for rainfed green water, irrigated green water, and irrigated blue water, plus VMR-associated green-water GEP. It converts monetary results to 2019 US dollars and aggregates country totals from crop-country rows for which the required components can be calculated. The country result retains every country in the boundary correspondence and records a `missing_reason` when its total cannot be calculated.

## Final outputs

`Data/Results/gep_agwater_crop_country_source_commercial_base_2019usd.csv` reports crop-by-country values and their water-source components in thousands of 2019 US dollars.

`Data/Results/gep_agwater_country_source_commercial_base_2019usd.csv` reports country values, coverage counts, and reasons for missing totals in thousands of 2019 US dollars.

`Data/Results/Submission/wateruse_ag_gep_commercial_base_2019usd.csv` reports country total `wateruse_ag_gep` in **2019 US dollars**, together with country identifiers and `missing_reason`.
