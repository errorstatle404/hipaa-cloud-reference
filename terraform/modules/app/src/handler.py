"""PHI reader: the application tier of the HIPAA reference build.

Runs inside private subnets and reaches S3 only through the VPC gateway
endpoint. It reads synthetic FHIR R4 bundles (Synthea) and returns aggregate
counts. It never returns or logs record contents.
"""

import json
import os
from collections import Counter

import boto3

s3 = boto3.client("s3")

BUCKET = os.environ["PHI_BUCKET"]
PREFIX = os.environ.get("PHI_PREFIX", "fhir/")
MAX_FILES = 50


def handler(event, context):
    max_files = min(int((event or {}).get("max_files", MAX_FILES)), MAX_FILES)

    paginator = s3.get_paginator("list_objects_v2")
    keys = []
    for page in paginator.paginate(Bucket=BUCKET, Prefix=PREFIX):
        keys += [o["Key"] for o in page.get("Contents", []) if o["Key"].endswith(".json")]

    resource_types = Counter()
    patients = 0
    files_read = 0
    for key in sorted(keys)[:max_files]:
        body = s3.get_object(Bucket=BUCKET, Key=key)["Body"].read()
        bundle = json.loads(body)
        files_read += 1
        for entry in bundle.get("entry", []):
            rtype = entry.get("resource", {}).get("resourceType", "Unknown")
            resource_types[rtype] += 1
            if rtype == "Patient":
                patients += 1

    result = {
        "bucket": BUCKET,
        "objects_found": len(keys),
        "objects_read": files_read,
        "patients": patients,
        "resource_types": dict(resource_types.most_common(10)),
    }
    # Aggregates only: safe to log.
    print(json.dumps(result))
    return result
