import os
from datetime import datetime
from zoneinfo import ZoneInfo

import boto3

PROCESSED_BUCKET = os.getenv("PROCESSED_BUCKET")


def handler(event, context):
    try:
        if "Records" not in event:
            return
        if "s3" not in event["Records"][0]:
            return

        s3_info = event["Records"][0]["s3"]
        bucket = s3_info["bucket"]["name"]
        key = s3_info["object"]["key"]
        file_name = key.split("/")[0]
        tmp_file_path = f"/tmp/{file_name}"

        s3 = boto3.resource("s3")
        s3.meta.client.download_file(bucket, key, tmp_file_path)
        with open(tmp_file_path, mode="a", encoding="utf-8") as f:
            now = datetime.now(ZoneInfo("Asia/Tokyo"))
            now_str = now.strftime("%Y/%m/%dT%H:%M:%S.%f%z")
            f.write(f"\n{now_str}")

        s3 = boto3.client("s3")
        s3.upload_file(tmp_file_path, PROCESSED_BUCKET, f"processed_{file_name}")
    except Exception as e:
        print(e)
