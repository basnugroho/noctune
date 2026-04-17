from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


ROOT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_ENV_PATH = ROOT_DIR / ".env"
DEFAULT_SCHEMA_PATH = ROOT_DIR / "sql" / "create_ttfb_results.sql"

DATETIME_COLUMNS = {
    "test_start_time",
    "test_end_time",
    "timestamp",
    "location_browser_timestamp",
    "location_saved_at",
}

TIME_COLUMNS = {"time_short"}

BOOLEAN_COLUMNS = {"battery_charging", "location_is_precise", "is_mobile"}

INTEGER_COLUMNS = {
    "sample_num",
    "http_code",
    "battery_level",
    "wifi_rssi",
    "wifi_channel",
    "signal_threshold",
    "config_ttfb_good_ms",
    "config_ttfb_warning_ms",
    "config_sample_count",
    "config_delay_seconds",
    "summary_good_count",
    "summary_warning_count",
    "summary_poor_count",
    "summary_total_tests",
    "summary_successful_tests",
    "summary_failed_tests",
}

DECIMAL_COLUMNS = {
    "ttfb_ms",
    "lookup_ms",
    "connect_ms",
    "total_ms",
    "location_lat",
    "location_lon",
    "location_accuracy",
    "location_altitude",
    "location_altitude_accuracy",
    "location_heading",
    "location_speed",
    "summary_mean_ttfb",
    "summary_median_ttfb",
    "summary_min_ttfb",
    "summary_max_ttfb",
    "summary_std_ttfb",
}

SCHEMA_CONSTRAINT_PREFIXES = {
    "PRIMARY",
    "UNIQUE",
    "KEY",
    "CONSTRAINT",
    "INDEX",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import TTFB CSV results into MySQL")
    parser.add_argument("csv_path", type=Path, help="Path to exported TTFB CSV file")
    parser.add_argument("--table", default="ttfb_results", help="Destination table name")
    parser.add_argument("--env-file", type=Path, default=DEFAULT_ENV_PATH, help="Path to .env file")
    parser.add_argument(
        "--schema-file",
        type=Path,
        default=DEFAULT_SCHEMA_PATH,
        help="Path to CREATE TABLE SQL file",
    )
    return parser.parse_args()


def load_env_file(env_path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    for line in env_path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        env[key.strip()] = value.strip()
    return env


def normalize_datetime(value: str) -> str:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed.strftime("%Y-%m-%d %H:%M:%S.%f")


def normalize_value(column: str, value: str) -> str:
    if value == "":
        return "NULL"

    if column in DATETIME_COLUMNS:
        return quote_sql(normalize_datetime(value))

    if column in TIME_COLUMNS:
        return quote_sql(value)

    if column in BOOLEAN_COLUMNS:
        lowered = value.strip().lower()
        if lowered in {"true", "1", "yes"}:
            return "1"
        if lowered in {"false", "0", "no"}:
            return "0"
        raise ValueError(f"Unsupported boolean value for {column}: {value}")

    if column in INTEGER_COLUMNS:
        return str(int(float(value)))

    if column in DECIMAL_COLUMNS:
        return str(float(value))

    return quote_sql(value)


def quote_sql(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace("'", "''").replace("\n", "\\n")
    return f"'{escaped}'"


def build_insert_sql(table: str, fieldnames: list[str], rows: Iterable[dict[str, str]]) -> str:
    column_sql = ", ".join(f"`{name}`" for name in fieldnames)
    values_sql: list[str] = []

    for row in rows:
        row_values = ", ".join(normalize_value(column, row[column]) for column in fieldnames)
        values_sql.append(f"({row_values})")

    return (
        f"INSERT INTO `{table}` ({column_sql})\nVALUES\n"
        + ",\n".join(values_sql)
        + "\nON DUPLICATE KEY UPDATE updated_at = CURRENT_TIMESTAMP;\n"
    )


def run_mysql_sql(mysql_env: dict[str, str], sql_text: str, database: str) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, encoding="utf-8") as tmp_file:
        tmp_file.write(sql_text)
        tmp_path = tmp_file.name

    env = os.environ.copy()
    env["MYSQL_PWD"] = mysql_env["DB_PASSWORD"]

    command = [
        "mysql",
        f"--host={mysql_env['DB_HOST']}",
        f"--port={mysql_env['DB_PORT']}",
        f"--user={mysql_env['DB_USERNAME']}",
        "--default-character-set=utf8mb4",
        database,
    ]

    try:
        with open(tmp_path, "r", encoding="utf-8") as sql_file:
            subprocess.run(command, env=env, stdin=sql_file, check=True)
    finally:
        Path(tmp_path).unlink(missing_ok=True)


def run_mysql_query(mysql_env: dict[str, str], sql_text: str, database: str) -> str:
    env = os.environ.copy()
    env["MYSQL_PWD"] = mysql_env["DB_PASSWORD"]

    command = [
        "mysql",
        f"--host={mysql_env['DB_HOST']}",
        f"--port={mysql_env['DB_PORT']}",
        f"--user={mysql_env['DB_USERNAME']}",
        "--default-character-set=utf8mb4",
        "--batch",
        "--skip-column-names",
        database,
        "-e",
        sql_text,
    ]
    completed = subprocess.run(command, env=env, capture_output=True, text=True, check=True)
    return completed.stdout


def extract_schema_columns(schema_sql: str) -> list[tuple[str, str]]:
    columns: list[tuple[str, str]] = []
    in_table_definition = False

    for raw_line in schema_sql.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        if stripped.upper().startswith("CREATE TABLE"):
            in_table_definition = True
            continue
        if not in_table_definition:
            continue
        if stripped.startswith(")"):
            break

        definition = stripped.rstrip(",")
        if not definition:
            continue

        first_token = definition.split(None, 1)[0].strip("`").upper()
        if first_token in SCHEMA_CONSTRAINT_PREFIXES:
            continue

        match = re.match(r"`?([A-Za-z_][A-Za-z0-9_]*)`?\s+", definition)
        if not match:
            continue

        columns.append((match.group(1), definition))

    return columns


def fetch_existing_columns(mysql_env: dict[str, str], table: str, database: str) -> set[str]:
    output = run_mysql_query(mysql_env, f"SHOW COLUMNS FROM `{table}`;", database)
    columns = {line.split("\t", 1)[0].strip() for line in output.splitlines() if line.strip()}
    return columns


def ensure_table_columns(mysql_env: dict[str, str], schema_sql: str, table: str, database: str) -> list[str]:
    schema_columns = extract_schema_columns(schema_sql)
    existing_columns = fetch_existing_columns(mysql_env, table, database)
    missing_definitions = [definition for column, definition in schema_columns if column not in existing_columns]

    if not missing_definitions:
        return []

    alter_sql = "ALTER TABLE `{table}`\n{clauses};\n".format(
        table=table,
        clauses=",\n".join(f"ADD COLUMN {definition}" for definition in missing_definitions),
    )
    run_mysql_sql(mysql_env, alter_sql, database)
    return [column for column, definition in schema_columns if definition in missing_definitions]


def main() -> None:
    args = parse_args()
    env_values = load_env_file(args.env_file)
    database = env_values["DB_DATABASE"]

    schema_sql = args.schema_file.read_text(encoding="utf-8")
    if args.table != "ttfb_results":
        schema_sql = schema_sql.replace("ttfb_results", args.table)
    run_mysql_sql(env_values, schema_sql, database)
    added_columns = ensure_table_columns(env_values, schema_sql, args.table, database)
    if added_columns:
        print(f"Added missing columns to {database}.{args.table}: {', '.join(added_columns)}")

    with args.csv_path.open("r", encoding="utf-8", newline="") as csv_file:
        reader = csv.DictReader(csv_file)
        fieldnames = list(reader.fieldnames or [])
        rows = list(reader)

    if not fieldnames:
        raise ValueError("CSV file does not contain a header row")

    insert_sql = build_insert_sql(args.table, fieldnames, rows)
    run_mysql_sql(env_values, insert_sql, database)

    print(f"Imported {len(rows)} rows into {database}.{args.table}")


if __name__ == "__main__":
    main()