"""Daily extract: pull every active board in companies.csv and load one snapshot to BigQuery.

Run with: python -m extract
"""
import csv
import os
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

from google.cloud import bigquery

from extract.load import load_postings, load_runs
from extract.sources import fetch_postings

SEED_PATH = Path(__file__).resolve().parent.parent / "dbt" / "seeds" / "companies.csv"


def main():
    project = os.environ.get("GCP_PROJECT_ID", "hiring-market-tracker")
    dataset = os.environ.get("RAW_DATASET", "raw")
    client = bigquery.Client(project=project)

    extracted_at = datetime.now(timezone.utc)
    snapshot_date = extracted_at.date()
    run_id = uuid.uuid4().hex
    with SEED_PATH.open() as f:
        companies = [c for c in csv.DictReader(f) if c["is_active"] == "true"]

    posting_rows, run_rows = [], []
    for company in companies:
        started = time.monotonic()
        run = {
            "run_id": run_id,
            "snapshot_date": snapshot_date.isoformat(),
            "extracted_at": extracted_at.isoformat(),
            "company_slug": company["company_slug"],
            "ats": company["ats"],
            "status": "success",
            "http_status": 200,
            "n_postings": 0,
            "error": None,
        }
        try:
            postings = fetch_postings(company["ats"], company["board_token"])
        except Exception as exc:
            # One broken board must not stop the other companies from loading.
            response = getattr(exc, "response", None)
            run.update(status="failed", http_status=getattr(response, "status_code", None), error=repr(exc)[:500])
            postings = []
        run["n_postings"] = len(postings)
        run["duration_ms"] = int((time.monotonic() - started) * 1000)
        run_rows.append(run)
        posting_rows += [
            {
                "snapshot_date": snapshot_date.isoformat(),
                "extracted_at": extracted_at.isoformat(),
                "run_id": run_id,
                "ats": company["ats"],
                "company_slug": company["company_slug"],
                "posting_id": str(p["id"]),
                "payload": p,
            }
            for p in postings
        ]
        print(f"{company['company_slug']:<16} {run['status']:<8} {run['n_postings']:>5} postings  {run['duration_ms']:>6} ms")

    failed = [r["company_slug"] for r in run_rows if r["status"] == "failed"]
    if posting_rows:
        load_postings(client, dataset, snapshot_date, posting_rows)
    load_runs(client, dataset, run_rows)
    print(f"\nsnapshot {snapshot_date}: {len(posting_rows)} postings from {len(run_rows) - len(failed)}/{len(run_rows)} companies loaded")
    if failed:
        print(f"failed: {', '.join(failed)}")
    # Fail the job only when nothing worked; partial failures are caught by the dbt completeness test.
    return 1 if len(failed) == len(run_rows) else 0


if __name__ == "__main__":
    sys.exit(main())
