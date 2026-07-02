import os
import json
import boto3
import pandas as pd
import awswrangler as wr
import uuid
import re
from datetime import timedelta
from datetime import datetime

def lambda_handler(event, context):
    s3 = boto3.client("s3")
    
    bucket_name = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']

    response = s3.get_object(Bucket=bucket_name, Key=key)
    file_content = response['Body'].read().decode('utf-8')
    data = json.loads(file_content)
    # with open("hn_raw_1780826334.json", 'r') as file: 
    #     data = json.load(file)

    users_list = []
    posts_list = []
    users_karma = {}

    for item in data:
        author = item.get("author")
        if not author:
            continue 

        tags = item.get("_tags", [])
        post_type = "unknown"
        for t in ["story", "comment", "poll", "job"]:
            if t in tags:
                post_type = t
                break

        raw_text = item.get("comment_text") or item.get("story_text") or ""
        clean_text = re.sub(r'<[^>]+>', '', raw_text) if raw_text else ""

        iso_time = item.get("created_at")
        if iso_time:
            dt = datetime.strptime(iso_time, "%Y-%m-%dT%H:%M:%SZ")
            year = dt.strftime("%Y")
            month = dt.strftime("%m")
            day = dt.strftime("%d")
        else:
            continue 

        points = item.get("points") or 0

        posts_list.append({
            "platform" : "Hacker News",
            "post_id": str(item.get("objectID")),
            "author_username": author,
            "content_text": clean_text,
            "created_at": iso_time, 
            "post_type": post_type,
            "year": year, "month": month, "day": day,
            "score": points
        })

        users_karma[author] = users_karma.get(author, 0) + points
        
        users_list.append({
            "user_id": str(uuid.uuid4()),
            "username": author,
            "platform": "Hacker News",
            "karma_score": users_karma[author], 
            "is_verified": pd.NA, "created_at": pd.NA, "user_followers":pd.NA
        })

    df_users = pd.DataFrame(users_list)
    df_users = df_users.sort_values(by='karma_score', ascending=False)
    df_users = df_users.drop_duplicates(subset=['username'], keep="first")
    df_posts = pd.DataFrame(posts_list).drop_duplicates(subset=['post_id'])

    silver_bucket = os.environ.get("SILVER_BUCKET_NAME", "NAME")
    silver_path = f"s3://{silver_bucket}/silver/"
    
    if not df_users.empty:
        wr.s3.to_parquet(df=df_users, path=f"{silver_path}users/", dataset=True, mode="append", partition_cols=['platform'])
        
    if not df_posts.empty:
        wr.s3.to_parquet(df=df_posts, path=f"{silver_path}posts/", dataset=True, mode="append", partition_cols=['year', 'month', 'day'])

    d = datetime.today() - timedelta(days=1)
        
    return {"statusCode": 200, 
            "body": f"HN: Processed {len(df_posts)} posts.", 
            "posts_path": f"{silver_path}posts/year={d.strftime('%Y')}/month={d.strftime('%m')}/day={d.strftime('%d')}/",
            "users_path": f"{silver_path}users/platform=Hacker News/",
            "date": f"{d.strftime('%Y-%m-%d')}"}

# if __name__=="__main__":
#     lambda_handler(None,None)