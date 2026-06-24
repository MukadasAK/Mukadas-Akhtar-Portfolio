 NHS A&E Performance Analysis

## Project overview
An end-to-end data analysis project using real NHS England
open data to examine A&E performance trends, seasonal
patterns, and trust-level variation across England from
2019 to 2026.

## Tools used
- Python (pandas) — combining 80+ monthly NHS Excel files
- SQL (SQLite) — data cleaning, transformation, and analysis
- Power BI — four-page interactive dashboard

## Key findings
- National 4-hour performance fell from 85.13% in 2019 to 75.69% in 2023
- 12-hour breach volumes increased 
- Winter months (Nov-Mar) show consistently lower performance
- Significant variation exists between trusts — top performer
  averaged 100 % vs bottom performer at 39.6%

## Dashboard pages
1. Executive summary — national KPIs and trend line
2. 2. Regional map — performance by ICS area
3. Trust league table — ranked with conditional formatting
4. Seasonal pattern — monthly demand and performance

## Data source
NHS England A&E Attendances and Emergency Admissions
monthly statistics — publicly available at
england.nhs.uk/statistics

## Files in this repo
- combine_nhs_files.py — Python script to merge source files
- 01_create_tables.sql — database schema
- 02_clean_data.sql — data cleaning and transformation
- 03_views_for_powerbi.sql — analytical views for dashboard
- NHS_AE_Insights.pdf — one-page findings summary

##****Page 1 of dashboard****
<img width="963" height="531" alt="image" src="https://github.com/user-attachments/assets/4719f331-ff13-4af1-b6e5-eeebbbb8aedf" />
