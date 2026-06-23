-- ============================================================
-- NHS A&E Performance Analysis
-- FILE 1 OF 3: Create Tables
-- Run this first, before anything else
-- ============================================================


-- ------------------------------------------------------------
-- DROP tables if you need to start fresh (comment out if not)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ae_monthly;
DROP TABLE IF EXISTS trust_reference;
DROP TABLE IF EXISTS dim_date;


-- ------------------------------------------------------------
-- TABLE 1: ae_monthly
-- One row per NHS Trust per month
-- This is your main fact table
-- ------------------------------------------------------------
CREATE TABLE ae_monthly (

    id              INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Time dimension
    period          TEXT NOT NULL,      -- Format: 'YYYY-MM' e.g. '2023-04'
    period_year     INTEGER,            -- e.g. 2023  (populated in cleaning step)
    period_month    INTEGER,            -- e.g. 4     (populated in cleaning step)

    -- Organisation dimension
    org_code        TEXT NOT NULL,      -- NHS Trust code e.g. 'RJ1', 'RRV'
    org_name        TEXT,               -- Full trust name

    -- A&E type breakdown (NHS splits A&E into 3 types)
    type1_att       INTEGER,            -- Type 1: Major A&E departments
    type2_att       INTEGER,            -- Type 2: Single specialty A&E (e.g. eye, dental)
    type3_att       INTEGER,            -- Type 3: Urgent treatment centres & minor injury units

    -- Totals
    total_att       INTEGER,            -- All attendances (type 1 + 2 + 3)
    total_adm       INTEGER,            -- Emergency admissions from A&E

    -- 4-hour performance (THE key NHS metric)
    seen_4hr        INTEGER,            -- Number of patients seen within 4 hours
    perf_pct        REAL,               -- 4-hr performance as % e.g. 76.3

    -- 12-hour waits (breach flag — serious performance concern)
    wait_12hr_dec   INTEGER,            -- 12hr waits from decision to admit
    wait_12hr_arr   INTEGER,            -- 12hr waits from arrival (added from 2020 onwards)

    -- Data quality flags (you'll set these in the cleaning step)
    is_valid        INTEGER DEFAULT 1,  -- 1 = clean row, 0 = flagged as suspect
    load_date       TEXT                -- When you imported this row

);


-- ------------------------------------------------------------
-- TABLE 2: trust_reference
-- One row per NHS Trust — reference/lookup table
-- Join this to ae_monthly on org_code
-- ------------------------------------------------------------
CREATE TABLE trust_reference (

    org_code        TEXT PRIMARY KEY,   -- Matches ae_monthly.org_code
    org_name        TEXT,
    org_type        TEXT,               -- e.g. 'NHS Trust', 'NHS Foundation Trust'

    -- Geography
    region          TEXT,               -- e.g. 'London', 'North West', 'South East'
    ics_code        TEXT,               -- Integrated Care System code
    ics_name        TEXT,               -- e.g. 'NHS Greater Manchester ICB'
    stp_code        TEXT,               -- Sustainability & Transformation Partnership

    -- For the Power BI map visual
    latitude        REAL,
    longitude       REAL,

    -- Status
    is_active       INTEGER DEFAULT 1,  -- 1 = still operating
    open_date       TEXT,
    close_date      TEXT

);


-- ------------------------------------------------------------
-- TABLE 3: dim_date
-- A date dimension table — makes time analysis much easier
-- in Power BI (filters by year, quarter, month name etc.)
-- ------------------------------------------------------------
CREATE TABLE dim_date (

    period          TEXT PRIMARY KEY,   -- 'YYYY-MM' — joins to ae_monthly.period
    period_year     INTEGER,
    period_month    INTEGER,
    month_name      TEXT,               -- e.g. 'April'
    month_abbr      TEXT,               -- e.g. 'Apr'
    quarter         INTEGER,            -- 1, 2, 3, or 4
    quarter_label   TEXT,               -- e.g. 'Q1 2023'
    nhs_fin_year    TEXT,               -- NHS financial year e.g. '2023/24'
                                        -- (NHS year runs Apr–Mar)
    nhs_fin_qtr     TEXT,               -- e.g. 'Q1 2023/24'
    is_winter       INTEGER,            -- 1 = Nov, Dec, Jan, Feb, Mar (winter months)
    sort_order      INTEGER             -- Numeric sort key for charts

);


-- ============================================================
-- INDEXES
-- These speed up your queries once the tables have data in them
-- ============================================================
CREATE INDEX idx_ae_period    ON ae_monthly(period);
CREATE INDEX idx_ae_org       ON ae_monthly(org_code);
CREATE INDEX idx_ae_period_org ON ae_monthly(period, org_code);


-- ============================================================
-- VERIFY: Run this after to confirm tables were created
-- ============================================================
SELECT
    name        AS table_name,
    'created'   AS status
FROM sqlite_master
WHERE type = 'table'
ORDER BY name;
