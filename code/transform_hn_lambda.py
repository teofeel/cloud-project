import pandas as pd
import awswrangler as wr
import os

def lambda_handler(event, context):

    gold_bucket = os.environ.get("GOLD_BUCKET_NAME", "NAME")
    gold_path = f"s3://{gold_bucket}/gold/"

    posts_path = event['responsePayload']['posts_path']
    users_path = event['responsePayload']['users_path']

    posts_df = wr.s3.read_parquet(path=posts_path, dataset=True)
    users_df = wr.s3.read_parquet(path=users_path, dataset=True)

    platform = "Hacker News"
    date = event['responsePayload']['date']

    total_rows = posts_df.shape[0] + users_df.shape[0]
    non_null_rows = posts_df.dropna().shape[0] + users_df.dropna().shape[0]
    dqs = round((non_null_rows / total_rows) * 100, 2) if total_rows > 0 else 0.0

    dqs_metric = {
        "date" : date,
        "platform" : platform,
        "dqs" : dqs
    }

    dqs_df = pd.DataFrame([dqs_metric])
    
    hn_posts_df = posts_df[posts_df['platform'] == platform].copy() if 'platform' in posts_df.columns else posts_df.copy()

    post_metrics = {
        "date": date,
        "platform": platform,
        "stories": int((hn_posts_df['post_type'] == "story").sum()),
        "comments": int((hn_posts_df['post_type'] == "comment").sum()),
        "jobs": int((hn_posts_df['post_type'] == "job").sum()),
        "polls": int((hn_posts_df['post_type'] == "poll").sum())
    }

    post_metrics_df = pd.DataFrame([post_metrics])

    top_jobs = hn_posts_df[hn_posts_df['post_type'] == "job"].nlargest(10, 'score').copy()
    top_jobs['rank'] = range(1, len(top_jobs) + 1)
    top_jobs['platform'] = platform
    top_jobs['date'] = date

    top_posts = hn_posts_df.nlargest(10, 'score').copy()
    top_posts['rank'] = range(1, len(top_posts) + 1)
    top_posts['platform'] = platform
    top_posts['date'] = date

    user_metrics = {
        "date" : date,
        "platform" : platform,
        "users" : users_df.shape[0]
    }

    user_metrics_df = pd.DataFrame([user_metrics])

    top_users = users_df.nlargest(10, 'karma_score').copy()
    top_users['rank'] = range(1, len(top_users) + 1)
    top_users['platform'] = platform
    top_users['date'] = date

    bottom_users = users_df.nsmallest(10, 'karma_score').copy()
    bottom_users['rank'] = range(1, len(bottom_users) + 1)
    bottom_users['platform'] = platform
    bottom_users['date'] = date

    if not post_metrics_df.empty:
        wr.s3.to_parquet(df=post_metrics_df, path=f"{gold_path}post_metrics/", dataset=True, mode='append', partition_cols=['platform', 'date'])
    if not top_jobs.empty:
        wr.s3.to_parquet(df=top_jobs, path=f"{gold_path}top_jobs/", dataset=True, mode='append', partition_cols=['platform', 'date'])
    if not top_posts.empty:
        wr.s3.to_parquet(df=top_posts, path=f"{gold_path}top_posts/", dataset=True, mode='append', partition_cols=['platform', 'date'])
    if not user_metrics_df.empty:
        wr.s3.to_parquet(df=user_metrics_df, path=f"{gold_path}user_metrics/", dataset=True, mode='append', partition_cols=['platform', 'date'])
    if not top_users.empty:
        wr.s3.to_parquet(df=top_users, path=f"{gold_path}top_users/", dataset=True, mode='append', partition_cols=['platform', 'date'])
    if not bottom_users.empty: 
        wr.s3.to_parquet(df=bottom_users, path=f"{gold_path}bottom_users/", dataset=True, mode='append', partition_cols=['platform', 'date'])
    if not dqs_df.empty: 
        wr.s3.to_parquet(df=dqs_df, path=f"{gold_path}KPI/", dataset=True, mode='append', partition_cols=['platform', 'date'])

    return {"statusCode": 200, "body" : "Success" }
