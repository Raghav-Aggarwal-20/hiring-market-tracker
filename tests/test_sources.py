import unittest
from unittest import mock

from extract import sources


class FetchPostingsTest(unittest.TestCase):
    def test_drops_description_fields_and_keeps_the_rest(self):
        jobs = [{"id": 1, "title": "Analytics Engineer", "content": "<p>long html</p>", "first_published": "2026-10-05"}]
        with mock.patch.dict(sources.FETCHERS, {"greenhouse": lambda token: jobs}):
            result = sources.fetch_postings("greenhouse", "elastic")
        self.assertEqual(result, [{"id": 1, "title": "Analytics Engineer", "first_published": "2026-10-05"}])

    def test_rejects_posting_without_id(self):
        with mock.patch.dict(sources.FETCHERS, {"ashby": lambda token: [{"title": "No id"}]}):
            with self.assertRaises(ValueError):
                sources.fetch_postings("ashby", "hex")



class FakeResponse:
    def __init__(self, body):
        self.body = body

    def raise_for_status(self):
        pass

    def json(self):
        return self.body


class FetchWorkdayTest(unittest.TestCase):
    def setUp(self):
        self.listing = [{"externalPath": f"/job/{i}", "title": f"Role {i}"} for i in range(25)]

    def post(self, url, json, timeout):
        page = self.listing[json["offset"]:json["offset"] + json["limit"]]
        # Like Workday: only the first page carries the real total.
        return FakeResponse({"total": self.total if json["offset"] == 0 else 0, "jobPostings": page})

    def get(self, url, timeout):
        return FakeResponse({"jobPostingInfo": {"startDate": "2026-11-13", "jobDescription": "<p>x</p>"}})

    def fetch(self, known):
        with mock.patch.object(sources.SESSION, "post", self.post), mock.patch.object(sources.SESSION, "get", self.get):
            return sources.fetch_workday("acme.wd1/Careers", known)

    def test_pages_and_fetches_detail_only_for_new_postings(self):
        self.total = 25
        jobs = {j["id"]: j for j in self.fetch(frozenset({"/job/0"}))}
        self.assertEqual(len(jobs), 25)
        self.assertNotIn("startDate", jobs["/job/0"])
        self.assertEqual(jobs["/job/24"]["startDate"], "2026-11-13")
        self.assertNotIn("jobDescription", jobs["/job/24"])

    def test_short_listing_fails_the_board(self):
        self.total = 40
        with self.assertRaises(ValueError):
            self.fetch(frozenset())

if __name__ == "__main__":
    unittest.main()
