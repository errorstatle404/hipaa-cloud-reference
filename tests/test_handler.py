"""Unit tests for the PHI reader Lambda. No AWS calls: S3 is mocked."""

import importlib
import io
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "terraform", "modules", "app", "src"))

BUNDLE = {
    "resourceType": "Bundle",
    "entry": [
        {"resource": {"resourceType": "Patient", "name": [{"family": "Synthetic"}]}},
        {"resource": {"resourceType": "Condition"}},
        {"resource": {"resourceType": "Observation"}},
        {"resource": {"resourceType": "Observation"}},
    ],
}


def load_handler(keys):
    fake_s3 = mock.MagicMock()
    fake_s3.get_paginator.return_value.paginate.return_value = [
        {"Contents": [{"Key": k} for k in keys]}
    ]
    fake_s3.get_object.side_effect = lambda Bucket, Key: {"Body": io.BytesIO(json.dumps(BUNDLE).encode())}
    with mock.patch.dict(os.environ, {"PHI_BUCKET": "test-bucket", "AWS_DEFAULT_REGION": "us-east-2"}), \
            mock.patch("boto3.client", return_value=fake_s3):
        import handler
        importlib.reload(handler)
    return handler, fake_s3


class HandlerTest(unittest.TestCase):
    def test_counts_patients_and_resources(self):
        handler, _ = load_handler(["fhir/a.json", "fhir/b.json", "fhir/readme.txt"])
        result = handler.handler({}, None)
        self.assertEqual(result["objects_found"], 2)
        self.assertEqual(result["patients"], 2)
        self.assertEqual(result["resource_types"]["Observation"], 4)

    def test_never_returns_record_contents(self):
        handler, _ = load_handler(["fhir/a.json"])
        result = json.dumps(handler.handler({}, None))
        self.assertNotIn("Synthetic", result)

    def test_caps_files_read(self):
        handler, s3 = load_handler([f"fhir/{i}.json" for i in range(80)])
        result = handler.handler({"max_files": 500}, None)
        self.assertEqual(result["objects_read"], 50)
        self.assertEqual(s3.get_object.call_count, 50)


if __name__ == "__main__":
    unittest.main()
