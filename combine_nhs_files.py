# ============================================================
# NHS A&E Data Combiner
# This script opens all 80 Excel files and combines them into
# one single CSV file ready to import into SQL
#
# HOW TO RUN THIS:
#   1. Install Python if you don't have it (python.org — download
#      the latest version, tick "Add to PATH" during install)
#   2. Open a terminal / command prompt
#   3. Run:  pip install pandas openpyxl
#   4. Put this script in your NHS_AE_Project folder
#   5. Run:  python combine_nhs_files.py
# ============================================================

import pandas as pd
import os
import glob

# ============================================================
# CHANGE THIS to the folder where your Excel files are saved
# Use forward slashes, even on Windows
# ============================================================
RAW_DATA_FOLDER = "raw_data"        # folder name if script is in same parent folder
OUTPUT_FILE     = "ae_combined.csv" # the single file this script will create


# ============================================================
# These are the column names this script will look for.
# NHS files are not consistent — they change column names
# slightly between years. This script handles that automatically.
# ============================================================

# Each entry below is a list of possible names for the same column
# The script tries each name and uses whichever one it finds
COLUMN_MAP = {
    "period":       ["Period", "period", "Month", "Date"],
    "org_code":     ["Org Code", "org_code", "Code", "Organisation Code", "ODS Code"],
    "org_name":     ["Org Name", "org_name", "Name", "Organisation Name", "Provider"],
    "type1_att":    ["Total Attendances Type 1", "Type 1 Departments - Major A&E",
                     "Type 1 A&E Att", "Att Type 1"],
    "type2_att":    ["Total Attendances Type 2", "Type 2 Departments - Single Specialty",
                     "Type 2 A&E Att", "Att Type 2"],
    "type3_att":    ["Total Attendances Type 3 and 4", "Type 3 Departments - Other A&E/UTC",
                     "Type 3 A&E Att", "Att Type 3"],
    "total_att":    ["Total Attendances", "Total A&E Att", "All Attendances",
                     "Total Type 1,2,3"],
    "total_adm":    ["Total Emergency Admissions", "Emergency Admissions",
                     "Total Admissions via A&E"],
    "seen_4hr":     ["Total attendances within 4 hours", "Seen within 4 hours",
                     "Within 4 hrs", "Number seen within 4 hours"],
    "perf_pct":     ["% within 4 hours", "Performance", "4 hr performance",
                     "Percentage in 4 hours", "% Seen Within 4 Hours"],
    "wait_12hr_dec":["Total patients who waited more than 12 hours from decision to admit",
                     "12 hour waits from decision to admit", "12hr DTA Waits",
                     "12+ hr DTA"],
    "wait_12hr_arr":["Total patients who waited more than 12 hours from arrival",
                     "12 hour waits from arrival", "12hr from arrival"],
}


# ============================================================
# MAIN SCRIPT — you don't need to change anything below here
# ============================================================

def find_column(df_columns, possible_names):
    """Find the first matching column name from a list of possibilities."""
    df_cols_lower = {col.strip().lower(): col for col in df_columns}
    for name in possible_names:
        if name.strip().lower() in df_cols_lower:
            return df_cols_lower[name.strip().lower()]
    return None


def find_header_row(df_raw):
    """
    NHS Excel files often have logos, titles, and blank rows
    at the top before the actual data starts.
    This finds the row where the real column headers are.
    """
    for i, row in df_raw.iterrows():
        # Look for a row that contains 'org' or 'period' or 'code' — that's the header
        row_str = " ".join([str(v).lower() for v in row.values if pd.notna(v)])
        if any(word in row_str for word in ["org code", "org name", "code", "period", "month"]):
            return i
    return 0  # fallback: assume first row is header


def process_file(filepath):
    """Open one Excel file and extract the data we need."""
    filename = os.path.basename(filepath)
    print(f"  Processing: {filename}")

    try:
        # First, open without headers to find where the data starts
        df_raw = pd.read_excel(filepath, header=None, sheet_name=0, nrows=20)
        header_row = find_header_row(df_raw)

        # Now read properly from the header row
        df = pd.read_excel(filepath, header=header_row, sheet_name=0)

        # Clean up column names (strip whitespace, newlines)
        df.columns = [str(c).strip().replace("\n", " ") for c in df.columns]

        # Drop completely empty rows
        df = df.dropna(how="all")

        # Build a clean output dataframe
        output = pd.DataFrame()

        for target_col, possible_names in COLUMN_MAP.items():
            matched = find_column(df.columns, possible_names)
            if matched:
                output[target_col] = df[matched]
            else:
                output[target_col] = None  # column not in this file — fill with NULL

        # Drop rows where org_code is blank (totals rows, blank rows)
        output = output.dropna(subset=["org_code"])
        output = output[output["org_code"].astype(str).str.strip() != ""]
        output = output[~output["org_code"].astype(str).str.lower().isin(
            ["total", "england", "grand total", "nan"]
        )]

        # Add source file name for debugging
        output["source_file"] = filename

        print(f"    -> {len(output)} rows extracted")
        return output

    except Exception as e:
        print(f"    !! ERROR with {filename}: {e}")
        return None


# Find all Excel files in the raw_data folder
excel_files = (
    glob.glob(os.path.join(RAW_DATA_FOLDER, "*.xlsx")) +
    glob.glob(os.path.join(RAW_DATA_FOLDER, "*.xls"))
)

if not excel_files:
    print(f"\nERROR: No Excel files found in '{RAW_DATA_FOLDER}' folder.")
    print("Make sure your Excel files are in that folder and try again.")
    exit()

print(f"\nFound {len(excel_files)} Excel files. Starting...\n")

# Process every file and collect the results
all_data = []
errors   = []

for filepath in sorted(excel_files):
    result = process_file(filepath)
    if result is not None and len(result) > 0:
        all_data.append(result)
    else:
        errors.append(os.path.basename(filepath))

# Combine everything into one dataframe
print(f"\nCombining all files...")
combined = pd.concat(all_data, ignore_index=True)

# Clean up the period column — standardise to YYYY-MM format
print("Standardising date format...")
combined["period"] = pd.to_datetime(
    combined["period"].astype(str), errors="coerce"
).dt.strftime("%Y-%m")

# Clean up numeric columns — remove commas, convert to numbers
numeric_cols = ["type1_att","type2_att","type3_att","total_att",
                "total_adm","seen_4hr","perf_pct",
                "wait_12hr_dec","wait_12hr_arr"]

for col in numeric_cols:
    if col in combined.columns:
        combined[col] = (
            combined[col]
            .astype(str)
            .str.replace(",", "", regex=False)
            .str.replace("%", "", regex=False)
            .str.strip()
        )
        combined[col] = pd.to_numeric(combined[col], errors="coerce")

# Sort by period then org
combined = combined.sort_values(["period", "org_code"], na_position="last")

# Remove duplicate rows (same trust, same month)
before = len(combined)
combined = combined.drop_duplicates(subset=["period", "org_code"], keep="last")
after = len(combined)
if before != after:
    print(f"  Removed {before - after} duplicate rows")

# Save to CSV
combined.to_csv(OUTPUT_FILE, index=False)

# ============================================================
# SUMMARY REPORT
# ============================================================
print(f"\n{'='*55}")
print(f"  DONE!")
print(f"{'='*55}")
print(f"  Files processed : {len(all_data)}")
print(f"  Total rows      : {len(combined):,}")
print(f"  Date range      : {combined['period'].min()} to {combined['period'].max()}")
print(f"  Unique trusts   : {combined['org_code'].nunique()}")
print(f"  Output file     : {OUTPUT_FILE}")

if errors:
    print(f"\n  Files with errors ({len(errors)}):")
    for e in errors:
        print(f"    - {e}")
    print("  These files may have unusual formatting. Open them manually.")

print(f"\n  Next step: Import '{OUTPUT_FILE}' into DB Browser for SQLite")
print(f"  Go to: File > Import > Table from CSV file")
print(f"  Table name: ae_monthly")
print(f"{'='*55}\n")
