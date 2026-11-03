"""Write one day's snapshot to the BigQuery raw dataset using load jobs (no DML, no streaming)."""
from google.cloud import bigquery

F = bigquery.SchemaField

POSTINGS_SCHEMA = [
    F("snapshot_date", "DATE", mode="REQUIRED"),
    F("extracted_at", "TIMESTAMP", mode="REQUIRED"),
    F("run_id", "STRING", mode="REQUIRED"),
    F("ats", "STRING", mode="REQUIRED"),
    F("company_slug", "STRING", mode="REQUIRED"),
    F("posting_id", "STRING", mode="REQUIRED"),
    F("payload", "JSON", mode="REQUIRED"),
]

RUNS_SCHEMA = [
    F("run_id", "STRING", mode="REQUIRED"),
    F("snapshot_date", "DATE", mode="REQUIRED"),
    F("extracted_at", "TIMESTAMP", mode="REQUIRED"),
    F("company_slug", "STRING", mode="REQUIRED"),
    F("ats", "STRING", mode="REQUIRED"),
    F("status", "STRING", mode="REQUIRED"),
    F("http_status", "INTEGER"),
    F("n_postings", "INTEGER", mode="REQUIRED"),
    F("duration_ms", "INTEGER", mode="REQUIRED"),
    F("error", "STRING"),
]


def _load(client, destination, rows, schema, write_disposition, cluster_by):
    config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition=write_disposition,
        time_partitioning=bigquery.TimePartitioning(field="snapshot_date"),
        clustering_fields=cluster_by,
    )
    client.load_table_from_json(rows, destination, job_config=config).result()


def load_postings(client, dataset, snapshot_date, rows):
    # Targeting the day's partition ($YYYYMMDD) with TRUNCATE makes a same-day rerun replace that day, not duplicate it.
    destination = f"{client.project}.{dataset}.job_postings${snapshot_date:%Y%m%d}"
    _load(client, destination, rows, POSTINGS_SCHEMA, "WRITE_TRUNCATE", ["company_slug"])


def load_runs(client, dataset, rows):
    # Runs are appended: every attempt is kept, and dbt uses the latest run per company per day.
    destination = f"{client.project}.{dataset}.extract_runs"
    _load(client, destination, rows, RUNS_SCHEMA, "WRITE_APPEND", ["company_slug"])
