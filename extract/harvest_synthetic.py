"""SYNTHETIC Harvest data: a made-up recruiting funnel on one company's real Greenhouse requisitions.

Real Harvest data (applications, stages, offers) needs the company's own API key, so this generates objects in
Harvest's v1 shapes instead and lands them in raw.harvest_* exactly as a real extractor would. The jobs are real
(keyed on the public board's internal_job_id = Harvest jobs.id) and so are their open and close dates; every
application, stage move and offer is invented. Swapping this file for a real Harvest client leaves dbt unchanged.

Run once with: python -m extract.harvest_synthetic   (deterministic: the same jobs give the same data)
"""
import os
import random
import uuid
from datetime import date, datetime, time, timedelta, timezone

from google.cloud import bigquery

COMPANY = "fivetran"
STAGES = ["Application Review", "Preliminary Phone Screen", "Hiring Manager Screen", "Assessment",
          "Onsite Interview", "Reference Check", "Offer"]
# Chance of moving from stage i to stage i+1.
PASS = [0.18, 0.55, 0.50, 0.55, 0.30, 0.85]
SOURCES = {  # name: (weight, multiplier on passing Application Review)
    "LinkedIn": (35, 1.0), "Company Website": (25, 0.9), "Indeed": (10, 0.6), "Referral": (8, 2.2),
    "Prospecting": (12, 1.6), "Agency": (3, 1.3), "Other": (7, 0.8),
}
APPS_PER_DAY = {"engineering": 3.0, "sales": 3.5, "marketing": 2.5, "data_analytics": 3.0, "product_design": 2.0}
FILL_RATE = 0.8  # share of closed postings treated as filled; the rest were cancelled
MAX_WINDOW_DAYS = 120

F = bigquery.SchemaField
SCHEMA = [F("snapshot_date", "DATE", mode="REQUIRED"), F("extracted_at", "TIMESTAMP", mode="REQUIRED"),
          F("run_id", "STRING", mode="REQUIRED"), F("company_slug", "STRING", mode="REQUIRED"),
          F("payload", "JSON", mode="REQUIRED")]


def ts(d, rng):
    return datetime.combine(d, time(rng.randint(8, 19), rng.randint(0, 59)), timezone.utc).isoformat()


def simulate_job(job, as_of):
    """job: dict with job_id, title, job_function, opened (date), closed (date or None). Returns stages, apps, offers."""
    jid = int(job["job_id"])
    rng = random.Random(jid)
    end = job["closed"] or as_of
    filled = job["closed"] is not None and rng.random() < FILL_RATE
    stages = [{"id": jid * 10 + i, "name": n, "priority": i, "job_id": jid, "interviews": []} for i, n in enumerate(STAGES)]
    start = max(job["opened"], end - timedelta(days=MAX_WINDOW_DAYS))
    window = (end - start).days + 1
    n_apps = max(3, int(rng.gauss(1, 0.25) * APPS_PER_DAY.get(job["job_function"], 1.5) * min(window, 60)))

    apps = []
    for k in range(n_apps):
        source = rng.choices(list(SOURCES), [w for w, _ in SOURCES.values()])[0]
        applied = start + timedelta(days=int(window * rng.random() ** 1.6))  # front-loaded, like real postings
        t, stage, outcome = applied, 0, "active"
        while stage < len(PASS):
            p = PASS[stage] * (SOURCES[source][1] if stage == 0 else 1)
            if rng.random() > p:
                outcome = "rejected"
                break
            nxt = t + timedelta(days=rng.randint(2, 8))
            if nxt > end:
                break
            t, stage = nxt, stage + 1
        apps.append({"k": k, "applied": applied, "stage": stage, "t": t, "outcome": outcome, "source": source})

    offers, hire = [], None
    if filled:
        # The hire is the furthest-along candidate whose last move fits before the posting came down.
        best = max(apps, key=lambda a: (a["stage"], -a["t"].toordinal()))
        best.update(stage=len(STAGES) - 1, t=min(max(best["t"], best["applied"] + timedelta(days=21)), end), outcome="hired")
        hire = best

    application_rows = []
    for a in apps:
        app_id = jid * 10000 + a["k"]
        rejected_at, reason, current = None, None, stages[a["stage"]]
        status = "active"
        if a is hire:
            status, current = "hired", None
        elif a["outcome"] == "rejected":
            status = "rejected"
            rejected_at = min(a["t"] + timedelta(days=rng.randint(1, 6)), end)
            reason = ("Lacking skill(s)/qualification(s)", "We rejected them") if rng.random() < 0.85 \
                else ("Withdrew", "They rejected us")
        elif job["closed"] is not None:  # posting came down: everyone still in process is closed out
            status, rejected_at = "rejected", end
            reason = ("Hired another candidate", "We rejected them") if filled else ("Position closed", "None specified")

        if a["stage"] == len(STAGES) - 1:
            accepted = a is hire
            offer_status = "accepted" if accepted else ("rejected" if status == "rejected" else "unresolved")
            if offer_status == "rejected":
                reason = ("Accepted another offer", "They rejected us")
            created = a["t"] - timedelta(days=rng.randint(0, 3))
            offers.append({
                "id": app_id, "version": 1, "application_id": app_id, "job_id": jid, "candidate_id": app_id + 7,
                "created_at": ts(created, rng), "sent_at": ts(created, rng),
                "resolved_at": ts(a["t"], rng) if offer_status != "unresolved" else None,
                "starts_at": (a["t"] + timedelta(days=rng.randint(14, 35))).isoformat() if accepted else None,
                "status": offer_status,
            })
        application_rows.append({
            "id": app_id, "candidate_id": app_id + 7, "prospect": False,
            "applied_at": ts(a["applied"], rng), "rejected_at": ts(rejected_at, rng) if rejected_at else None,
            "last_activity_at": ts(rejected_at or a["t"], rng),
            "source": {"id": list(SOURCES).index(a["source"]) + 1, "public_name": a["source"]},
            "rejection_reason": {"name": reason[0], "type": {"name": reason[1]}} if reason else None,
            "jobs": [{"id": jid, "name": job["title"]}],
            "status": status,
            "current_stage": {"id": current["id"], "name": current["name"]} if current else None,
        })
    return stages, application_rows, offers


def main():
    project = os.environ.get("GCP_PROJECT_ID", "hiring-market-tracker")
    raw, analytics = os.environ.get("RAW_DATASET", "raw"), os.environ.get("DBT_DATASET", "analytics")
    client = bigquery.Client(project=project)
    sql = f"""
        select job_id, title, job_function, published_date as opened, closed_date as closed,
               (select max(last_seen_date) from `{project}.{analytics}.dim_posting`) as as_of
        from `{project}.{analytics}.dim_requisition`
        where company_slug = '{COMPANY}'
    """
    jobs = [dict(r) for r in client.query(sql).result()]
    out = {"job_stages": [], "applications": [], "offers": []}
    for job in jobs:
        s, a, o = simulate_job(job, job["as_of"])
        out["job_stages"] += s
        out["applications"] += a
        out["offers"] += o

    extracted_at = datetime.now(timezone.utc)
    meta = {"snapshot_date": extracted_at.date().isoformat(), "extracted_at": extracted_at.isoformat(),
            "run_id": uuid.uuid4().hex, "company_slug": COMPANY}
    for endpoint, objs in out.items():
        config = bigquery.LoadJobConfig(schema=SCHEMA, write_disposition="WRITE_TRUNCATE",
                                        time_partitioning=bigquery.TimePartitioning(field="snapshot_date"))
        rows = [{**meta, "payload": o} for o in objs]
        client.load_table_from_json(rows, f"{project}.{raw}.harvest_{endpoint}", job_config=config).result()
        print(f"raw.harvest_{endpoint:<13} {len(rows):>6} rows")
    print(f"{len(jobs)} {COMPANY} jobs, as of {jobs[0]['as_of']}")


if __name__ == "__main__":
    main()
