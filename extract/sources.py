"""Fetch open postings from public ATS job-board APIs.

Returns postings as the API sent them, minus large description fields.
All renaming, typing and cleaning happens in dbt, not here.
"""
from concurrent.futures import ThreadPoolExecutor

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

USER_AGENT = "hiring-market-tracker/1.0 (+https://github.com/Raghav-Aggarwal-20/hiring-market-tracker)"
TIMEOUT_SECONDS = 30

# Description HTML is ~90% of each payload and unused in v1.
DROP_FIELDS = {
    "greenhouse": {"content"},
    "ashby": {"descriptionHtml", "descriptionPlain"},
    "workday": set(),  # fetch_workday never keeps jobDescription
}

# Workday caps a search page at 20 postings.
WORKDAY_PAGE = 20
# shortcut: caps detail calls per board per run; a backlog bigger than this finishes on later runs.
WORKDAY_MAX_DETAILS = 1500


def _session():
    session = requests.Session()
    retry = Retry(total=3, backoff_factor=2, status_forcelist=(429, 500, 502, 503, 504), allowed_methods=("GET", "POST"))  # Workday search is a read-only POST
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
    # pay_transparency=true adds structured pay_input_ranges; each range's HTML blurb is boilerplate, so it's dropped.
    jobs = _get_jobs(
        f"https://boards-api.greenhouse.io/v1/boards/{board_token}/jobs",
        {"content": "true", "pay_transparency": "true"},
    )
    for job in jobs:
        for pay_range in job.get("pay_input_ranges") or []:
            pay_range.pop("blurb", None)
    return jobs


def fetch_ashby(board_token):
    return _get_jobs(f"https://api.ashbyhq.com/posting-api/job-board/{board_token}", {"includeCompensation": "true"})


def _workday_detail(base, external_path):
    response = SESSION.get(base + external_path, timeout=TIMEOUT_SECONDS)
    response.raise_for_status()
    info = response.json()["jobPostingInfo"]
    info.pop("jobDescription", None)
    return info


def fetch_workday(board_token, known_ids=frozenset()):
    """board_token is "<host>/<site>", e.g. "workday.wd5/Workday". known_ids: postings that already have detail."""
    host, site = board_token.split("/")
    base = f"https://{host}.myworkdayjobs.com/wday/cxs/{host.split('.')[0]}/{site}"
    jobs, total, offset = {}, None, 0
    while total is None or offset < total:
        response = SESSION.post(
            f"{base}/jobs", json={"appliedFacets": {}, "limit": WORKDAY_PAGE, "offset": offset, "searchText": ""},
            timeout=TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        page = response.json()
        # Only the first page reports the real total; later pages often say 0.
        total = page["total"] if total is None else total
        if not page.get("jobPostings"):
            break
        for job in page["jobPostings"]:
            # Some boards list stubs with only a req ID and no page (CrowdStrike, 2026-11-13); nothing to track.
            if "externalPath" in job:
                jobs[job["externalPath"]] = {"id": job["externalPath"], **job}
        offset += WORKDAY_PAGE
    # A short listing would look like closures downstream, so fail the board instead.
    if len(jobs) < total * 0.99:
        raise ValueError(f"workday/{board_token}: got {len(jobs)} of {total} postings")

    # The search list has no posting date or req ID; fetch those once, on a posting's first sighting.
    new = [p for p in jobs if p not in known_ids][:WORKDAY_MAX_DETAILS]

    def detail(external_path):
        try:
            return external_path, _workday_detail(base, external_path)
        except (requests.RequestException, KeyError, ValueError):
            return external_path, None  # retried on the next run, since it stays out of known_ids

    with ThreadPoolExecutor(max_workers=4) as pool:
        for external_path, info in pool.map(detail, new):
            if info:
                jobs[external_path].update(info)
    return list(jobs.values())


FETCHERS = {"greenhouse": fetch_greenhouse, "ashby": fetch_ashby, "workday": fetch_workday}


def fetch_postings(ats, board_token, known_ids=frozenset()):
    """Return a list of posting dicts for one board, with description fields removed."""
    drop = DROP_FIELDS[ats]
    fetch = FETCHERS[ats]
    postings = []
    for job in fetch(board_token, known_ids) if ats == "workday" else fetch(board_token):
        if job.get("id") is None:
            raise ValueError(f"{ats}/{board_token}: posting without an id")
        postings.append({k: v for k, v in job.items() if k not in drop})
    return postings
