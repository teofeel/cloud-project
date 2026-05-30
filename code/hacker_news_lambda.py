import boto3
import json
import urllib
import os
import time

def lambda_handler(event, context):
    s3 = boto3.client("s3")
    bucket_name = os.environ["S3_BUCKET_NAME"]
    
    end_time = int(time.time())
    start_time = end_time - 86400
    
    all_hits = []
    
    interval = 1800 
    current_start = start_time
    
    while current_start < end_time:
        current_end = current_start + interval
        page = 0
        
        while page < 10:
            url = f"https://hn.algolia.com/api/v1/search_by_date?numericFilters=created_at_i>={current_start},created_at_i<{current_end}&page={page}&hitsPerPage=100"
            
            try:
                with urllib.request.urlopen(url) as response:
                    data = json.loads(response.read().decode("utf-8"))
            except Exception:
                break
                
            hits = data.get("hits", [])
            if not hits:
                break
                
            all_hits.extend(hits)
            page += 1
            
        current_start = current_end
        
    s3.put_object(
        Bucket=bucket_name,
        Key=f"hn_raw_{int(time.time())}.json",
        Body=json.dumps(all_hits)
    )
    
    return {
        "statusCode": 200,
        "body": json.dumps(f"Successfully collected {len(all_hits)} items.")
    }