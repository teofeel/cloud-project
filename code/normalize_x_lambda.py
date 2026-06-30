import os
import pandas as pd
import awswrangler as wr
import uuid
import urllib.parse
from datetime import datetime

def lambda_handler(event, context):
    records = event
    
    if 'Records' not in event:
        return {"statusCode": 200, "body": "No S3 records found."}
        
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'], encoding='utf-8')
    s3_path = f"s3://{bucket}/{key}"

    silver_bucket = os.environ.get("SILVER_BUCKET_NAME", "NAME")
    silver_path = f"s3://{silver_bucket}/silver/"
    #df_raw = pd.read_csv("Bitcoin_tweets_dataset_2.csv")
    total_processed = 0
    
    try:
        df_chunks = wr.s3.read_csv(s3_path, chunksize=50000)

        for df_chunk in df_chunks:
            users_list = []
            posts_list = []

            for _, row in df_chunk.iterrows():
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
                    "year": year, "month": month, "day": day,
                    "score": pd.NA
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
                    "is_verified":  str(row.get("user_verified")) if pd.notna(row.get("user_verified")) else pd.NA,
                    "created_at": user_created_at_iso,
                    "user_followers": row.get("user_followers", pd.NA)
                })
                
            df_users = pd.DataFrame(users_list).drop_duplicates(subset=['username'])
            df_posts = pd.DataFrame(posts_list).drop_duplicates(subset=['post_id'])

        
            if not df_users.empty:
                df_users['is_verified'] = df_users['is_verified'].astype('string')
                wr.s3.to_parquet(df=df_users, path=f"{silver_path}users/", dataset=True, mode="append", partition_cols=['platform'])
                
            if not df_posts.empty:
                wr.s3.to_parquet(df=df_posts, path=f"{silver_path}posts/", dataset=True, mode="append", partition_cols=['year', 'month', 'day'])
                
            total_processed += len(df_posts)
            print(f"Successfully collected {total_processed} tweets until now...")

    except Exception as e:
        print(f"Error while processing file: {e}")
        return  {"statusCode":500, "body":str(e)}
    return {"statusCode": 200, "body": f"X: Processed {len(df_posts)} tweets."}

# if __name__=="__main__":
#     lambda_handler(None, None)