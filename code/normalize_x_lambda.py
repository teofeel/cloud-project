import os
import pandas as pd
import awswrangler as wr
import uuid
from datetime import datetime

def lambda_handler(event, context):
    records = event
    
    if not records:
        return {"statusCode": 200, "body": "No records to process."}
        
    df_raw = pd.DataFrame(records)
    #df_raw = pd.read_csv("Bitcoin_tweets_dataset_2.csv")
    users_list = []
    posts_list = []
    
    for _, row in df_raw.iterrows():
        author = row.get("user_name")  
        if not author:
            continue
            
        created_time_raw = row.get("date")
        try:
            dt = datetime.strptime(created_time_raw, "%Y-%m-%d %H:%M:%S")
            year = dt.strftime("%Y")
            month = dt.strftime("%m")
            day = dt.strftime("%d")
            iso_time = dt.isoformat() + "Z"
        except Exception:
            continue

        posts_list.append({
            "post_id": str(uuid.uuid4()), 
            "author_username": author,
            "content_text": str(row.get("text", "")),
            "created_at": iso_time,
            "post_type": "tweet",
            "year": year, "month": month, "day": day
        })

        try:
            dt = datetime.strptime(row.get("user_created"), "%Y-%m-%d %H:%M:%S")
            user_created_at_iso = dt.isoformat() + "Z"
        except Exception:
            print(Exception)
            continue

        users_list.append({
            "user_id": str(uuid.uuid4()),
            "username": author,
            "platform": "X",
            "karma_score": pd.NA,
            "is_verified": row.get("user_verified", pd.NA),
            "created_at": user_created_at_iso
        })
        
    df_users = pd.DataFrame(users_list).drop_duplicates(subset=['username'])
    df_posts = pd.DataFrame(posts_list).drop_duplicates(subset=['post_id'])
    
    silver_bucket = os.environ.get("SILVER_BUCKET_NAME", "NAME")
    silver_path = f"s3://{silver_bucket}/silver/"
    
    if not df_users.empty:
        wr.s3.to_parquet(df=df_users, path=f"{silver_path}users/", dataset=True, mode="append", partition_cols=['platform'])
        
    if not df_posts.empty:
        wr.s3.to_parquet(df=df_posts, path=f"{silver_path}posts/", dataset=True, mode="append", partition_cols=['year', 'month', 'day'])
        
    return {"statusCode": 200, "body": f"X: Processed {len(df_posts)} tweets."}

# if __name__=="__main__":
#     lambda_handler(None, None)