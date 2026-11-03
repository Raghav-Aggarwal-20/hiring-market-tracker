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


if __name__ == "__main__":
    unittest.main()
