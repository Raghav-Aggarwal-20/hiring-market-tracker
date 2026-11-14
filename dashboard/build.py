"""Build the static dashboard: query the rpt_ tables in BigQuery and write one self-contained HTML page.

Run: python -m dashboard.build   (writes dashboard/site/index.html)
"""

import json
import os
from decimal import Decimal
from pathlib import Path

from google.cloud import bigquery

PROJECT = os.environ.get("GCP_PROJECT_ID", "hiring-market-tracker")
DATASET = os.environ.get("DBT_DATASET", "analytics")
HERE = Path(__file__).parent
OUT = HERE / "site" / "index.html"

QUERIES = {
    "companies": """
        select company_name, peer_lens, open_postings, data_roles,
               remote_postings, hybrid_postings, onsite_postings, workplace_not_stated,
               median_age_days, median_salary_midpoint_usd,
               share_engineering, share_sales, share_data_analytics, share_people_hr,
               share_customer, share_marketing, share_product_design, share_g_and_a
        from `{ds}.rpt_company_summary`
        order by open_postings desc
    """,
    # One row per posting, only the two fields the client needs for exact median age per filter.
    "ages": "select peer_lens, company_name, reported_age_days as age from `{ds}.rpt_postings_current`",
    "data_roles": """
        select company_name, peer_lens, title, data_role_family_label as family, workplace_label as workplace,
               us_label as location, seniority_label as seniority,
               if(is_pay_usable, salary_midpoint_usd, null) as pay_mid, reported_age_days as age, job_url
        from `{ds}.rpt_postings_current`
        where is_data_role
        order by age
    """,
    # Failed extract days are left out; their counts are NULL by design.
    "daily": """
        select snapshot_date as day, company_name, peer_lens, open_postings as open, new_postings as new_n,
               closed_postings as closed
        from `{ds}.rpt_company_daily`
        where is_active and is_successful
        order by snapshot_date
    """,
    "health": """
        select company_name, peer_lens, status_label, latest_status, postings_extracted,
               last_successful_date, latest_snapshot_date, share_pay_usable, share_workplace_not_stated
        from `{ds}.rpt_pipeline_health`
        order by company_name
    """,
    # SYNTHETIC Harvest funnel for one company (see extract/harvest_synthetic.py).
    "funnel": """
        select stage_order, stage_name, sum(applications_reached) as reached
        from `{ds}.fct_requisition_funnel` group by 1, 2 order by 1
    """,
    "sources": """
        select source_name as source, count(*) as apps, countif(furthest_stage_order >= 1) as screened, countif(is_hired) as hires
        from `{ds}.fct_applications` group by 1
    """,
    "fill": """
        select count(*) as reqs, countif(requisition_status = 'filled') as filled,
               countif(requisition_status != 'open') as closed,
               approx_quantiles(days_to_fill, 2)[offset(1)] as median_days
        from `{ds}.fct_time_to_fill`
    """,
}


def fetch():
    client = bigquery.Client(project=PROJECT)
    config = bigquery.QueryJobConfig(maximum_bytes_billed=1_000_000_000)
    ds = f"{PROJECT}.{DATASET}"
    return {
        name: [dict(row) for row in client.query(sql.format(ds=ds), job_config=config).result()]
        for name, sql in QUERIES.items()
    }


def main():
    data = fetch()
    # A page built from empty tables would publish a blank dashboard; fail the run instead.
    assert all(data[k] for k in QUERIES), {k: len(v) for k, v in data.items()}
    assert sum(c["open_postings"] for c in data["companies"]) == len(data["ages"])
    # Equal on a clean day; lower when a company's extract failed (its postings stay open but it has no daily row).
    last_day = max(r["day"] for r in data["daily"])
    assert sum(r["open"] for r in data["daily"] if r["day"] == last_day) <= len(data["ages"])

    html = (HERE / "template.html").read_text()
    OUT.parent.mkdir(exist_ok=True)
    # "</" inside a <script> block would end it early if a job title ever contained "</script>".
    # BigQuery NUMERIC arrives as Decimal; it must stay a number or JS sorts pay as text.
    to_json = lambda o: float(o) if isinstance(o, Decimal) else str(o)
    payload = json.dumps(data, default=to_json).replace("</", "<\\/")
    OUT.write_text(html.replace("__DATA__", payload))
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB, {len(data['ages'])} postings)")


if __name__ == "__main__":
    main()
