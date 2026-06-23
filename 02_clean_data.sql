-- ============================================================
-- NHS A&E Performance Analysis
-- FILE 2 OF 3: Clean & Enrich Data
-- Run this AFTER you have imported your CSV data into ae_monthly
-- ============================================================


-- ============================================================
-- STEP 1: CHECK WHAT YOU IMPORTED
-- Run these first to understand your raw data
-- ============================================================

-- How many rows came in?
SELECT COUNT(*) AS total_rows FROM ae_monthly;

-- What date range do you have?
SELECT
    MIN(period) AS earliest_period,
    MAX(period) AS latest_period,
    COUNT(DISTINCT period) AS total_months
FROM ae_monthly;

-- How many trusts?
SELECT COUNT(DISTINCT org_code) AS total_trusts FROM ae_monthly;

-- Spot any nulls in key columns?
SELECT
    SUM(CASE WHEN period   IS NULL THEN 1 ELSE 0 END) AS null_period,
    SUM(CASE WHEN org_code IS NULL THEN 1 ELSE 0 END) AS null_org_code,
    SUM(CASE WHEN total_att IS NULL THEN 1 ELSE 0 END) AS null_total_att,
    SUM(CASE WHEN perf_pct  IS NULL THEN 1 ELSE 0 END) AS null_perf_pct
FROM ae_monthly;


-- ============================================================
-- STEP 2: FIX THE PERIOD COLUMN
-- The NHS files often have dates like 'April 2023' or '01/04/2023'
-- We need 'YYYY-MM' format throughout
-- ============================================================

-- If your period came in as 'April 2023' style, run this:
UPDATE ae_monthly
SET period =
    SUBSTR(period, -4) || '-' ||
    CASE SUBSTR(period, 1, 3)
        WHEN 'Jan' THEN '01'
        WHEN 'Feb' THEN '02'
        WHEN 'Mar' THEN '03'
        WHEN 'Apr' THEN '04'
        WHEN 'May' THEN '05'
        WHEN 'Jun' THEN '06'
        WHEN 'Jul' THEN '07'
        WHEN 'Aug' THEN '08'
        WHEN 'Sep' THEN '09'
        WHEN 'Oct' THEN '10'
        WHEN 'Nov' THEN '11'
        WHEN 'Dec' THEN '12'
    END
WHERE period LIKE '%20__'   -- matches 'April 2023' style
  AND period NOT LIKE '____-__'; -- skip already-correct rows

-- Verify: all periods should now look like '2023-04'
SELECT DISTINCT period FROM ae_monthly ORDER BY period LIMIT 20;


-- ============================================================
-- STEP 3: POPULATE DERIVED COLUMNS
-- Fill in year, month — easier to work with than the text period
-- ============================================================

UPDATE ae_monthly
SET
    period_year  = CAST(SUBSTR(period, 1, 4) AS INTEGER),
    period_month = CAST(SUBSTR(period, 6, 2) AS INTEGER);

-- Verify
SELECT period, period_year, period_month FROM ae_monthly LIMIT 5;


-- ============================================================
-- STEP 4: CALCULATE perf_pct WHERE IT IS MISSING
-- Some NHS files give you raw counts but not the percentage.
-- Calculate it from seen_4hr / total_att
-- ============================================================

UPDATE ae_monthly
SET perf_pct = ROUND(seen_4hr * 100.0 / total_att, 2)
WHERE perf_pct IS NULL
  AND total_att IS NOT NULL
  AND total_att > 0
  AND seen_4hr  IS NOT NULL;


-- ============================================================
-- STEP 5: CALCULATE total_att WHERE IT IS MISSING
-- Sometimes total is missing but type breakdowns are there
-- ============================================================

UPDATE ae_monthly
SET total_att = COALESCE(type1_att, 0)
              + COALESCE(type2_att, 0)
              + COALESCE(type3_att, 0)
WHERE total_att IS NULL
  AND (type1_att IS NOT NULL
    OR type2_att IS NOT NULL
    OR type3_att IS NOT NULL);


-- ============================================================
-- STEP 6: FLAG SUSPECT ROWS
-- Don't delete bad data — flag it so you can filter it out
-- ============================================================

-- Flag rows where performance % is impossible (>100 or negative)
UPDATE ae_monthly
SET is_valid = 0
WHERE perf_pct > 100
   OR perf_pct < 0;

-- Flag rows where seen_4hr > total_att (impossible)
UPDATE ae_monthly
SET is_valid = 0
WHERE seen_4hr > total_att;

-- Flag rows with zero attendances (likely a reporting gap)
UPDATE ae_monthly
SET is_valid = 0
WHERE total_att = 0
   OR total_att IS NULL;

-- Check how many rows are flagged
SELECT
    is_valid,
    COUNT(*) AS row_count
FROM ae_monthly
GROUP BY is_valid;


-- ============================================================
-- STEP 7: POPULATE THE DIM_DATE TABLE
-- This fills in one row per month across your full date range
-- Makes Power BI time intelligence work properly
-- ============================================================

-- Clear it first if re-running
DELETE FROM dim_date;

-- Insert one row per period that exists in your data
INSERT INTO dim_date (
    period, period_year, period_month,
    month_name, month_abbr, quarter, quarter_label,
    nhs_fin_year, nhs_fin_qtr,
    is_winter, sort_order
)
SELECT DISTINCT
    period,
    CAST(SUBSTR(period, 1, 4) AS INTEGER)                   AS period_year,
    CAST(SUBSTR(period, 6, 2) AS INTEGER)                   AS period_month,

    CASE CAST(SUBSTR(period, 6, 2) AS INTEGER)
        WHEN 1  THEN 'January'   WHEN 2  THEN 'February'
        WHEN 3  THEN 'March'     WHEN 4  THEN 'April'
        WHEN 5  THEN 'May'       WHEN 6  THEN 'June'
        WHEN 7  THEN 'July'      WHEN 8  THEN 'August'
        WHEN 9  THEN 'September' WHEN 10 THEN 'October'
        WHEN 11 THEN 'November'  WHEN 12 THEN 'December'
    END                                                      AS month_name,

    CASE CAST(SUBSTR(period, 6, 2) AS INTEGER)
        WHEN 1  THEN 'Jan' WHEN 2  THEN 'Feb' WHEN 3  THEN 'Mar'
        WHEN 4  THEN 'Apr' WHEN 5  THEN 'May' WHEN 6  THEN 'Jun'
        WHEN 7  THEN 'Jul' WHEN 8  THEN 'Aug' WHEN 9  THEN 'Sep'
        WHEN 10 THEN 'Oct' WHEN 11 THEN 'Nov' WHEN 12 THEN 'Dec'
    END                                                      AS month_abbr,

    -- Calendar quarter
    CASE CAST(SUBSTR(period, 6, 2) AS INTEGER)
        WHEN 1  THEN 4  WHEN 2  THEN 4  WHEN 3  THEN 4
        WHEN 4  THEN 1  WHEN 5  THEN 1  WHEN 6  THEN 1
        WHEN 7  THEN 2  WHEN 8  THEN 2  WHEN 9  THEN 2
        WHEN 10 THEN 3  WHEN 11 THEN 3  WHEN 12 THEN 3
    END                                                      AS quarter,

    -- NHS quarter label (Q1 = Apr-Jun)
    'Q' || CASE CAST(SUBSTR(period, 6, 2) AS INTEGER)
        WHEN 4  THEN '1' WHEN 5  THEN '1' WHEN 6  THEN '1'
        WHEN 7  THEN '2' WHEN 8  THEN '2' WHEN 9  THEN '2'
        WHEN 10 THEN '3' WHEN 11 THEN '3' WHEN 12 THEN '3'
        WHEN 1  THEN '4' WHEN 2  THEN '4' WHEN 3  THEN '4'
    END || ' ' ||
    -- NHS financial year label (e.g. '2023/24')
    CASE WHEN CAST(SUBSTR(period, 6, 2) AS INTEGER) >= 4
        THEN SUBSTR(period, 1, 4) || '/' || SUBSTR(CAST(CAST(SUBSTR(period, 1, 4) AS INTEGER) + 1 AS TEXT), 3, 2)
        ELSE CAST(CAST(SUBSTR(period, 1, 4) AS INTEGER) - 1 AS TEXT) || '/' || SUBSTR(SUBSTR(period, 1, 4), 3, 2)
    END                                                      AS nhs_fin_qtr,

    -- NHS financial year (Apr to Mar)
    CASE WHEN CAST(SUBSTR(period, 6, 2) AS INTEGER) >= 4
        THEN SUBSTR(period, 1, 4) || '/' || SUBSTR(CAST(CAST(SUBSTR(period, 1, 4) AS INTEGER) + 1 AS TEXT), 3, 2)
        ELSE CAST(CAST(SUBSTR(period, 1, 4) AS INTEGER) - 1 AS TEXT) || '/' || SUBSTR(SUBSTR(period, 1, 4), 3, 2)
    END                                                      AS nhs_fin_year,

    -- Winter flag (Nov–Mar are winter pressure months)
    CASE WHEN CAST(SUBSTR(period, 6, 2) AS INTEGER) IN (11, 12, 1, 2, 3)
        THEN 1 ELSE 0
    END                                                      AS is_winter,

    -- Numeric sort key (e.g. 202304 for April 2023)
    CAST(REPLACE(period, '-', '') AS INTEGER)                AS sort_order

FROM ae_monthly
ORDER BY period;

-- Verify
SELECT * FROM dim_date ORDER BY period LIMIT 12;


-- ============================================================
-- STEP 8: FINAL QUALITY CHECK
-- ============================================================

SELECT
    'ae_monthly'        AS table_name,
    COUNT(*)            AS total_rows,
    SUM(CASE WHEN is_valid = 1 THEN 1 ELSE 0 END) AS valid_rows,
    SUM(CASE WHEN is_valid = 0 THEN 1 ELSE 0 END) AS flagged_rows,
    MIN(period)         AS earliest,
    MAX(period)         AS latest,
    COUNT(DISTINCT org_code) AS trusts
FROM ae_monthly

UNION ALL

SELECT
    'dim_date',
    COUNT(*), COUNT(*), 0,
    MIN(period), MAX(period), NULL
FROM dim_date;
