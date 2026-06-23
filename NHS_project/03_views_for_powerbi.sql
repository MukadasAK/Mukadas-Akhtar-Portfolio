-- ============================================================
-- NHS A&E Performance Analysis
-- FILE 3 OF 3: Analysis Views for Power BI
-- Run this last — these become your Power BI data sources
-- ============================================================


-- ============================================================
-- VIEW 1: vw_national_monthly
-- One row per month — national totals and performance
-- Used for: headline KPI cards, main time-series line chart
-- ============================================================
DROP VIEW IF EXISTS vw_national_monthly;

CREATE VIEW vw_national_monthly AS
SELECT
    m.period,
    d.period_year,
    d.period_month,
    d.month_name,
    d.quarter_label,
    d.nhs_fin_year,
    d.is_winter,
    d.sort_order,

    -- Volume metrics
    SUM(m.total_att)                                        AS total_attendances,
    SUM(m.type1_att)                                        AS type1_attendances,
    SUM(m.total_adm)                                        AS total_admissions,
    SUM(m.seen_4hr)                                         AS seen_within_4hr,
    SUM(m.wait_12hr_dec)                                    AS waits_12hr,

    -- Performance
    ROUND(SUM(m.seen_4hr) * 100.0 / SUM(m.total_att), 1)  AS perf_pct_4hr,

    -- Breach rate (12-hr waits as % of all attendances)
    ROUND(SUM(m.wait_12hr_dec) * 100.0
          / NULLIF(SUM(m.total_att), 0), 2)                AS breach_rate_pct,

    -- Rolling 12-month average performance (window function)
    ROUND(AVG(
        ROUND(SUM(m.seen_4hr) * 100.0 / SUM(m.total_att), 1)
    ) OVER (
        ORDER BY m.period
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ), 1)                                                    AS rolling_12m_avg,

    COUNT(DISTINCT m.org_code)                              AS trusts_reporting

FROM ae_monthly m
JOIN dim_date d ON m.period = d.period
WHERE m.is_valid = 1
GROUP BY m.period, d.period_year, d.period_month, d.month_name,
         d.quarter_label, d.nhs_fin_year, d.is_winter, d.sort_order
ORDER BY m.period;


-- ============================================================
-- VIEW 2: vw_trust_summary
-- One row per Trust — their average performance across all time
-- Used for: league table, regional map
-- ============================================================
DROP VIEW IF EXISTS vw_trust_summary;

CREATE VIEW vw_trust_summary AS
WITH trust_stats AS (
    SELECT
        m.org_code,
        m.org_name,
        COALESCE(t.region, 'Unknown')                       AS region,
        COALESCE(t.ics_name, 'Unknown')                     AS ics_name,
        t.latitude,
        t.longitude,

        COUNT(DISTINCT m.period)                            AS months_reported,
        SUM(m.total_att)                                    AS total_attendances,
        SUM(m.seen_4hr)                                     AS total_seen_4hr,
        SUM(m.total_adm)                                    AS total_admissions,
        SUM(m.wait_12hr_dec)                                AS total_12hr_waits,

        ROUND(SUM(m.seen_4hr) * 100.0
              / NULLIF(SUM(m.total_att), 0), 1)             AS avg_perf_pct,

        ROUND(AVG(m.perf_pct), 1)                          AS mean_monthly_perf,

        MIN(m.perf_pct)                                     AS worst_month_perf,
        MAX(m.perf_pct)                                     AS best_month_perf

    FROM ae_monthly m
    LEFT JOIN trust_reference t ON m.org_code = t.org_code
    WHERE m.is_valid = 1
    GROUP BY m.org_code, m.org_name, t.region, t.ics_name, t.latitude, t.longitude
)
SELECT
    org_code,
    org_name,
    region,
    ics_name,
    latitude,
    longitude,
    months_reported,
    total_attendances,
    total_admissions,
    total_12hr_waits,
    avg_perf_pct,
    mean_monthly_perf,
    worst_month_perf,
    best_month_perf,

    -- National rank (1 = best performing)
    RANK() OVER (ORDER BY avg_perf_pct DESC)                AS national_rank,

    -- Rank within region
    RANK() OVER (
        PARTITION BY region
        ORDER BY avg_perf_pct DESC
    )                                                        AS regional_rank,

    -- Performance band (for colour coding in Power BI)
    CASE
        WHEN avg_perf_pct >= 95 THEN 'Meeting target'
        WHEN avg_perf_pct >= 85 THEN 'Near target'
        WHEN avg_perf_pct >= 75 THEN 'Below target'
        ELSE                         'Significantly below'
    END                                                      AS performance_band

FROM trust_stats
ORDER BY national_rank;


-- ============================================================
-- VIEW 3: vw_trust_monthly
-- One row per Trust per month — full detail
-- Used for: drill-through pages, trust deep-dive
-- ============================================================
DROP VIEW IF EXISTS vw_trust_monthly;

CREATE VIEW vw_trust_monthly AS
SELECT
    m.period,
    d.period_year,
    d.period_month,
    d.month_name,
    d.nhs_fin_year,
    d.is_winter,
    d.sort_order,

    m.org_code,
    m.org_name,
    COALESCE(t.region, 'Unknown')                           AS region,
    COALESCE(t.ics_name, 'Unknown')                         AS ics_name,

    m.total_att,
    m.type1_att,
    m.total_adm,
    m.seen_4hr,
    m.wait_12hr_dec                                         AS waits_12hr,
    m.perf_pct,

    -- Month-on-month performance change for this trust
    ROUND(
        m.perf_pct - LAG(m.perf_pct) OVER (
            PARTITION BY m.org_code
            ORDER BY m.period
        ), 1
    )                                                        AS perf_mom_change,

    -- 3-month rolling average per trust
    ROUND(AVG(m.perf_pct) OVER (
        PARTITION BY m.org_code
        ORDER BY m.period
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 1)                                                    AS rolling_3m_avg,

    -- Performance band
    CASE
        WHEN m.perf_pct >= 95 THEN 'Meeting target'
        WHEN m.perf_pct >= 85 THEN 'Near target'
        WHEN m.perf_pct >= 75 THEN 'Below target'
        ELSE                       'Significantly below'
    END                                                      AS performance_band

FROM ae_monthly m
JOIN dim_date d ON m.period = d.period
LEFT JOIN trust_reference t ON m.org_code = t.org_code
WHERE m.is_valid = 1
ORDER BY m.org_code, m.period;


-- ============================================================
-- VIEW 4: vw_seasonal_pattern
-- Average by calendar month across all years
-- Used for: seasonal bar chart
-- ============================================================
DROP VIEW IF EXISTS vw_seasonal_pattern;

CREATE VIEW vw_seasonal_pattern AS
SELECT
    d.period_month,
    d.month_name,
    d.month_abbr,
    d.is_winter,

    ROUND(AVG(national.total_att), 0)                       AS avg_attendances,
    ROUND(AVG(national.perf_pct_4hr), 1)                   AS avg_4hr_perf,
    ROUND(AVG(national.waits_12hr), 0)                     AS avg_12hr_waits,
    COUNT(*)                                                 AS years_of_data

FROM vw_national_monthly national
JOIN dim_date d ON national.period = d.period
GROUP BY d.period_month, d.month_name, d.month_abbr, d.is_winter
ORDER BY d.period_month;


-- ============================================================
-- VIEW 5: vw_year_on_year
-- Annual summary with year-on-year comparison
-- Used for: YoY column chart
-- ============================================================
DROP VIEW IF EXISTS vw_year_on_year;

CREATE VIEW vw_year_on_year AS
WITH yearly AS (
    SELECT
        d.period_year                                       AS yr,
        d.nhs_fin_year,
        SUM(m.total_att)                                    AS total_attendances,
        SUM(m.seen_4hr)                                     AS total_seen_4hr,
        SUM(m.wait_12hr_dec)                                AS total_12hr_waits,
        ROUND(SUM(m.seen_4hr) * 100.0
              / NULLIF(SUM(m.total_att), 0), 1)             AS perf_pct,
        COUNT(DISTINCT m.org_code)                          AS trusts_reporting

    FROM ae_monthly m
    JOIN dim_date d ON m.period = d.period
    WHERE m.is_valid = 1
    GROUP BY d.period_year, d.nhs_fin_year
)
SELECT
    yr,
    nhs_fin_year,
    total_attendances,
    total_seen_4hr,
    total_12hr_waits,
    perf_pct,
    trusts_reporting,

    LAG(perf_pct)          OVER (ORDER BY yr)               AS prev_year_perf,
    LAG(total_attendances) OVER (ORDER BY yr)               AS prev_year_att,
    LAG(total_12hr_waits)  OVER (ORDER BY yr)               AS prev_year_12hr,

    ROUND(perf_pct -
          LAG(perf_pct) OVER (ORDER BY yr), 1)              AS perf_change_pp,

    ROUND((total_attendances - LAG(total_attendances) OVER (ORDER BY yr))
          * 100.0
          / NULLIF(LAG(total_attendances) OVER (ORDER BY yr), 0), 1) AS att_growth_pct

FROM yearly
ORDER BY yr;


-- ============================================================
-- VERIFY ALL VIEWS WERE CREATED
-- ============================================================
SELECT
    name        AS view_name,
    'ready'     AS status
FROM sqlite_master
WHERE type = 'view'
ORDER BY name;


-- ============================================================
-- QUICK SENSE-CHECK — run these after the views are created
-- ============================================================

-- National trend (top 10 most recent months)
SELECT period, total_attendances, perf_pct_4hr, rolling_12m_avg
FROM vw_national_monthly
ORDER BY period DESC
LIMIT 10;

-- Top 5 and bottom 5 trusts
SELECT national_rank, org_name, region, avg_perf_pct, performance_band
FROM vw_trust_summary
WHERE national_rank <= 5

UNION ALL

SELECT national_rank, org_name, region, avg_perf_pct, performance_band
FROM vw_trust_summary
ORDER BY national_rank DESC
LIMIT 5;

-- Year on year summary
SELECT yr, perf_pct, perf_change_pp, total_12hr_waits
FROM vw_year_on_year;
