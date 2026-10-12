# Rebuilding the page in Power BI

`dashboard.html` is the finished browser version. This guide recreates the same one-page layout in Power BI Desktop (about an hour).

## 1. Load the data
Get data, then Text/CSV. Load all three files from `data/`:
`wait_by_hour_dow.csv`, `wait_by_zone.csv`, `wav_by_borough_uber.csv`. No relationships are needed.

## 2. Add columns and measures (Modeling, New column / New measure)

On `wait_by_hour_dow`:
```
Day = SWITCH(wait_by_hour_dow[dow], 1,"Mon", 2,"Tue", 3,"Wed", 4,"Thu", 5,"Fri", 6,"Sat", 7,"Sun")
```
Then select the `Day` column, Column tools, Sort by column, `dow`.

On `wait_by_zone`:
```
Long waits = wait_by_zone[trips] * wait_by_zone[pct_wait_over_10min] / 100
Reliability = IF(wait_by_zone[pct_dropped_negative] > 3, "More than 3% excluded", "OK")
```

Measures (table `wait_by_zone`):
```
Weighted p90 =
DIVIDE(SUMX(wait_by_zone, wait_by_zone[p90_min] * wait_by_zone[trips]),
       SUM(wait_by_zone[trips]))

Share of all long waits =
DIVIDE(SUM(wait_by_zone[Long waits]), CALCULATE(SUM(wait_by_zone[Long waits]), ALL(wait_by_zone)))
```
Label any borough-level percentile built this way as approximate: percentiles cannot be averaged exactly.

## 3. Build the four visuals

1. **Heatmap (top):** Matrix. Rows `Day`, columns `req_hour`, values `p90_min` (Average, which is one row per cell). Cell elements, Background color, Rules or gradient: minimum pale blue-grey (#E6EFF3), midpoint amber (#F1C77F), maximum red (#C4351C). Turn off row and column subtotals. Add a slicer or bookmark toggle for `p50_min`.
2. **Zones (left):** Clustered bar chart, axis `Zone`, value `p90_min`, filtered to Top 12 by `p90_min`. Colour by `Reliability` so zones with more than 3% excluded rows stand out. Add a second bar chart filtered to Top 12 by `Long waits` (sum). Put the two on a bookmark toggle, or stack them.
3. **Accessibility (right):** Clustered bar chart from `wav_by_borough_uber`, axis `Borough`, legend `segment`, value `pct_over_10min`. Filter out `N/A`, `EWR` and `Unknown`. WAV colour #2E3C9C, other riders #9AA7B4. Add a Card for Uber citywide share over 10 minutes (22.9% vs 9.8%, from the SQL output).
4. **Text box (bottom):** the limits: Uber only for accessibility, no unmatched requests or cancellations in the data, 1.3% of trips excluded for impossible request times.

## 4. Finish
- Title the page "Who waits longest for a ride in New York?" and add a text box: "Independent project. Public NYC TLC data, April 2026."
- Hide gridlines, keep fonts at 12 pt or larger, and give every visual a plain-language title.
- Export a PDF or PNG of the page and add it to the repo next to `dashboard_preview.png`. Publish the `.pbix` only if the file stays small.
