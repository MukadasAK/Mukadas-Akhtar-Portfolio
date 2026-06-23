from pathlib import Path
import pandas as pd
import re

BASE_FOLDER = Path(r"C:\Users\User\Desktop\NHS_AE_Project")
RAW_FOLDER = BASE_FOLDER / "raw_data"

OUTPUT_FILE = BASE_FOLDER / "combined_for_sql_clean2.csv"
FAILED_LOG = BASE_FOLDER / "failed_files_log.csv"
PROCESSED_LOG = BASE_FOLDER / "processed_files_log.csv"

CONVERT_PERCENTAGES_TO_100 = False


def clean_column_name(name):
    name = str(name).strip().lower()
    name = name.replace("&", "and")
    name = re.sub(r"[^a-z0-9]+", "_", name)
    name = re.sub(r"_+", "_", name)
    name = name.strip("_")
    return name if name else "column"


def make_unique_columns(columns):
    seen = {}
    final = []

    for col in columns:
        if col not in seen:
            seen[col] = 0
            final.append(col)
        else:
            seen[col] += 1
            final.append(f"{col}_{seen[col]}")

    return final


def normalize_cell(value):
    if pd.isna(value):
        return ""
    value = str(value).strip().lower()
    value = value.replace(":", "")
    value = re.sub(r"\s+", " ", value)
    return value


def find_metadata(raw, label):
    label = label.lower().replace(":", "").strip()

    for _, row in raw.iterrows():
        values = list(row)

        for i, value in enumerate(values):
            text = normalize_cell(value)

            if text == label and i + 1 < len(values):
                return values[i + 1]

    return None


def find_header_row(raw):
    max_rows = min(120, len(raw))

    for i in range(max_rows):
        row_values = [normalize_cell(v) for v in raw.iloc[i].tolist()]

        has_code = any(
            v in ["code", "org code", "organisation code", "organization code", "provider code", "ods code"]
            or v.endswith(" code")
            for v in row_values
        )

        has_name = any(
            v in ["name", "org name", "organisation name", "organization name", "provider name", "site name"]
            or v.endswith(" name")
            for v in row_values
        )

        has_ae_data = any("type 1" in v for v in row_values) or any("total" in v for v in row_values) or any("attendance" in v for v in row_values)

        if has_code and has_name and has_ae_data:
            return i

    return None


def read_excel_file(file):
    last_error = None

    engines_to_try = [None]

    if file.suffix.lower() == ".xls":
        engines_to_try.append("xlrd")
    else:
        engines_to_try.append("openpyxl")
        engines_to_try.append("calamine")

    for engine in engines_to_try:
        try:
            if engine is None:
                excel = pd.ExcelFile(file)
            else:
                excel = pd.ExcelFile(file, engine=engine)

            return excel, engine

        except Exception as e:
            last_error = e

    raise last_error


files = []
for pattern in ["*.xls", "*.xlsx", "*.xlsm"]:
    files.extend(RAW_FOLDER.rglob(pattern))

files = [
    f for f in files
    if not f.name.startswith("~$")
    and "combined_for_sql" not in f.name.lower()
]

print("Excel files found:", len(files))

all_data = []
failed_files = []
processed_files = []

for file in files:
    try:
        print("\nChecking:", file.name)

        excel, engine = read_excel_file(file)

        matched_sheet = None
        matched_raw = None
        matched_header_row = None

        for sheet in excel.sheet_names:
            try:
                if engine is None:
                    raw = pd.read_excel(file, sheet_name=sheet, header=None, dtype=object)
                else:
                    raw = pd.read_excel(file, sheet_name=sheet, header=None, dtype=object, engine=engine)

                header_row = find_header_row(raw)

                if header_row is not None:
                    matched_sheet = sheet
                    matched_raw = raw
                    matched_header_row = header_row
                    break

            except Exception:
                continue

        if matched_raw is None:
            raise Exception("Could not find provider table in any sheet")

        raw = matched_raw
        header_row = matched_header_row

        print("Using sheet:", matched_sheet)
        print("Header row:", header_row + 1)

        parent_rows = []

        if header_row - 2 >= 0:
            parent_rows.append(raw.iloc[header_row - 2].ffill().fillna("").astype(str).str.strip())

        if header_row - 1 >= 0:
            parent_rows.append(raw.iloc[header_row - 1].ffill().fillna("").astype(str).str.strip())

        sub_row = raw.iloc[header_row].fillna("").astype(str).str.strip()

        columns = []

        for col_index, sub in enumerate(sub_row):
            sub = str(sub).strip()
            sub_norm = normalize_cell(sub)

            if sub_norm in ["code", "region", "name", "org code", "organisation code", "organization code", "provider code", "ods code", "org name", "organisation name", "organization name", "provider name"]:
                col_name = sub
            else:
                parts = []

                for parent in parent_rows:
                    value = str(parent.iloc[col_index]).strip()
                    value_norm = normalize_cell(value)

                    if value_norm and value_norm not in ["nan", "provider level data", ""]:
                        parts.append(value)

                if sub and normalize_cell(sub) not in ["nan", ""]:
                    parts.append(sub)

                clean_parts = []
                for p in parts:
                    if normalize_cell(p) not in [normalize_cell(x) for x in clean_parts]:
                        clean_parts.append(p)

                col_name = "_".join(clean_parts)

            columns.append(clean_column_name(col_name))

        columns = make_unique_columns(columns)

        df = raw.iloc[header_row + 1:].copy()
        df.columns = columns

        df = df.dropna(how="all")

        if "code" in df.columns:
            df = df[df["code"].astype(str).str.lower().str.strip() != "code"]
            df = df[df["code"].notna()]

        df = df.replace("-", pd.NA)

        period = find_metadata(raw, "Period")
        published = find_metadata(raw, "Published")
        revised = find_metadata(raw, "Revised")

        df.insert(0, "source_file", file.name)
        df.insert(1, "source_sheet", matched_sheet)
        df.insert(2, "period", period)
        df.insert(3, "published", published)
        df.insert(4, "revised", revised)

        if CONVERT_PERCENTAGES_TO_100:
            percent_cols = [
                col for col in df.columns
                if "percentage" in col or "percent" in col
            ]

            for col in percent_cols:
                df[col] = pd.to_numeric(df[col], errors="coerce") * 100

        all_data.append(df)

        processed_files.append({
            "file": file.name,
            "sheet_used": matched_sheet,
            "header_row": header_row + 1,
            "rows_added": len(df)
        })

    except Exception as e:
        failed_files.append({
            "file": file.name,
            "error": str(e)
        })


if all_data:
    combined = pd.concat(all_data, ignore_index=True, sort=False)
    combined.to_csv(OUTPUT_FILE, index=False, encoding="utf-8-sig")

    print("\nDONE")
    print("Clean combined CSV created here:")
    print(OUTPUT_FILE)
    print("Total rows:", len(combined))
else:
    print("No files were successfully combined.")


if processed_files:
    pd.DataFrame(processed_files).to_csv(PROCESSED_LOG, index=False, encoding="utf-8-sig")

if failed_files:
    pd.DataFrame(failed_files).to_csv(FAILED_LOG, index=False, encoding="utf-8-sig")

    print("\nSome files still failed.")
    print("Failed log created here:")
    print(FAILED_LOG)

    print("\nFailed files:")
    for item in failed_files:
        print(item["file"], "=>", item["error"])

print("\nProcessed log:")
print(PROCESSED_LOG)

input("\nPress Enter to close...")