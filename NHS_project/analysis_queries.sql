/*
NHS A&E Performance Analysis
SQL Analysis Queries

This file contains the main SQL queries used to analyze NHS England A&E performance data.
The queries support the Power BI dashboard by preparing national trends, rolling averages,
trust rankings, seasonal patterns, and year-on-year comparisons.

Main tables used:
- ae_monthly
- ae_combined
*/

Query 1 — Monthly national trend
The big picture: how has 4-hour performance changed over time nationally?
SELECT
  period,
  SUM(total_att)                          AS total_attendances,
  SUM(seen_4hr)                           AS seen_in_4hrs,
  ROUND(
    SUM(seen_4hr) * 100.0 / SUM(total_att), 1
  )                                        AS perf_pct_national,
  SUM(wait_12hr)                          AS total_12hr_waits
FROM ae_monthly
GROUP BY period
ORDER BY period;

________________________________________
Query 2 — Rolling 12-month average (window function)
Smooths out seasonal spikes so you can see the real trend. This uses a window function — a key SQL skill.
WITH monthly_national AS (
  SELECT
    period,
    ROUND(SUM(seen_4hr)*100.0/SUM(total_att),1) AS perf_pct
  FROM ae_monthly
  GROUP BY period
)
SELECT
  period,
  perf_pct,
  ROUND(AVG(perf_pct) OVER (
    ORDER BY period
    ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
  ), 1)                          AS rolling_12m_avg
FROM monthly_national
ORDER BY period;
I used a rolling 12 month average to smooth out short term monthly fluctuations and show the longer term direction of national A&E performance. While the monthly percentage shows the performance in each individual month, the rolling average shows whether the wider trend is improving or declining over the previous year.
________________________________________
Query 3 — Trust performance ranking (window function)
Rank every NHS Trust by their average performance — great for the league table in Power BI.
WITH trust_avg AS (
  SELECT
    org_code,
    org_name,
    region,
    COUNT(DISTINCT period) AS months_reported,
    SUM(total_att) AS total_attendances,

    -- raw value for ranking
    SUM(seen_4hr) * 100.0 / NULLIF(SUM(total_att), 0) AS avg_4hr_perf_raw

  FROM ae_combined
  WHERE period >= '2023-01'
  GROUP BY org_code, org_name, region
)
SELECT
  org_code,
  org_name,
  region,
  months_reported,
  ROUND(avg_4hr_perf_raw, 1) AS avg_4hr_perf,
  total_attendances,

  RANK() OVER (
    ORDER BY avg_4hr_perf_raw DESC
  ) AS national_rank,

  RANK() OVER (
    PARTITION BY region
    ORDER BY avg_4hr_perf_raw DESC
  ) AS regional_rank

FROM trust_avg
ORDER BY national_rank;

________________________________________
Query 4 — Seasonal demand pattern
Does winter really cause more A&E pressure? This proves it with data.
SELECT
  SUBSTR(period, 6, 2)                   AS month_num,
  CASE SUBSTR(period, 6, 2)
    WHEN '01' THEN 'January'
    WHEN '02' THEN 'February'
    WHEN '03' THEN 'March'
    WHEN '04' THEN 'April'
    WHEN '05' THEN 'May'
    WHEN '06' THEN 'June'
    WHEN '07' THEN 'July'
    WHEN '08' THEN 'August'
    WHEN '09' THEN 'September'
    WHEN '10' THEN 'October'
    WHEN '11' THEN 'November'
    WHEN '12' THEN 'December'
  END                                    AS month_name,
  ROUND(AVG(total_att), 0)              AS avg_attendances,
  ROUND(AVG(perf_pct), 1)              AS avg_4hr_perf
FROM ae_monthly
GROUP BY month_num
ORDER BY month_num;
I created a seasonality query by extracting the month from each reporting period. This allowed me to compare average attendances and 4 hour performance across calendar months. The purpose was to see whether winter or summer months show different pressure patterns in A&E performance.
________________________________________
Query 5 — Year-on-year comparison (CTE pipeline)
Shows how each year compared to the last. A multi-step CTE pipeline — impressive to show in an interview.
WITH yearly AS (
  SELECT
    SUBSTR(period, 1, 4)                  AS yr,
    SUM(total_att)                        AS attendances,
    SUM(seen_4hr)                         AS seen_4hr,
    SUM(wait_12hr)                        AS breaches_12hr,
    ROUND(SUM(seen_4hr)*100.0/SUM(total_att), 1) AS perf_pct
  FROM ae_monthly
  GROUP BY yr
),
with_prev AS (
  SELECT
    yr,
    attendances,
    perf_pct,
    breaches_12hr,
    LAG(perf_pct) OVER (ORDER BY yr)      AS prev_year_perf,
    LAG(attendances) OVER (ORDER BY yr)   AS prev_year_att
  FROM yearly
)
SELECT
  yr,
  attendances,
  perf_pct,
  prev_year_perf,
  ROUND(perf_pct - prev_year_perf, 1)    AS perf_change_pp,
  breaches_12hr
FROM with_prev
ORDER BY yr;

I created a yearly comparison query to summarise total attendances, 4 hour performance, and 12 hour waits by year. I used the LAG() window function to bring in the previous year’s performance, then calculated the year on year change in percentage points. This helps identify whether performance improved or declined compared with the previous year

