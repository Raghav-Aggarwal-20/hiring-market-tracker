"""Fetch open postings from public ATS job-board APIs.

Returns postings as the API sent them, minus large description fields.
All renaming, typing and cleaning happens in dbt, not here.
"""
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

USER_AGENT = "hiring-market-tracker/1.0 (+https://github.com/Raghav-Aggarwal-20/hiring-market-tracker)"
TIMEOUT_SECONDS = 30

# Description HTML is ~90% of each payload and unused in v1.
DROP_FIELDS = {
    "greenhouse": {"content"},
    "ashby": {"descriptionHtml", "descriptionPlain"},
}


def _session():
    session = requests.Session()
    retry = Retry(total=3, backoff_factor=2, status_forcelist=(429, 500, 502, 503, 504), allowed_methods=("GET",))
    session.mount("https://", HTTPAdapter(max_retries=retry))
    session.headers["User-Agent"] = USER_AGENT
    return session


SESSION = _session()


def _get_jobs(url, params):
    response = SESSION.get(url, params=params, timeout=TIMEOUT_SECONDS)
    response.raise_for_status()
    jobs = response.json().get("jobs")
    if not isinstance(jobs, list):
        raise ValueError(f"unexpected response shape from {url}: no 'jobs' list")
    return jobs


def fetch_greenhouse(board_token):
    # content=true is the only way to get departments and offices; the description itself is dropped later.
    return _get_jobs(f"https://boards-api.greenhouse.io/v1/boards/{board_token}/jobs", {"content": "true"})


def fetch_ashby(board_token):
    return _get_jobs(f"https://api.ashbyhq.com/posting-api/job-board/{board_token}", {"includeCompensation": "true"})


FETCHERS = {"greenhouse": fetch_greenhouse, "ashby": fetch_ashby}


def fetch_postings(ats, board_token):
    """Return a list of posting dicts for one board, with description fields removed."""
    drop = DROP_FIELDS[ats]
    postings = []
    for job in FETCHERS[ats](board_token):
        if job.get("id") is None:
            raise ValueError(f"{ats}/{board_token}: posting without an id")
        postings.append({k: v for k, v in job.items() if k not in drop})
    return postings
