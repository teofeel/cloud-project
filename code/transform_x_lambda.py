import pandas as pd
import awswrangler as wr
import os

def lambda_handler(event, context):

    gold_bucket = os.environ.get("GOLD_BUCKET_NAME", "NAME")
    gold_path = f"s3://{gold_bucket}/gold/"

    silver_bucket = os.environ.get("SILVER_BUCKET_NAME", "NAME")
    silver_path = f"s3://{silver_bucket}/silver/"

    platform = "X"

    user_metrics_buffer = []
    top_users_buffer = []
    dqs_buffer = []

    for chunk in wr.s3.read_parquet(path=f"{silver_path}users/platform=X/", dataset=True, chunked=50000):
        chunk['date'] = pd.to_datetime(chunk['created_at']).dt.strftime('%Y-%m-%d')
        chunk['user_followers'] = pd.to_numeric(chunk['user_followers'], errors='coerce')

        user_metrics_buffer.append(
            chunk.groupby('date').size().reset_index(name='users')
        )

        top_users_buffer.append(
            chunk.sort_values('user_followers', ascending=False)
            .groupby('date')
            .head(10)
        )

        chunk['_non_null'] = chunk.drop(columns=['_non_null'], errors='ignore') \
                                  .apply(lambda row: row.notna().all(), axis=1).astype(int)
        dqs_buffer.append(
            chunk.groupby('date').agg(
                total=('_non_null', 'count'),
                non_null=('_non_null', 'sum')
            ).reset_index()
        )

    user_metrics_df = (
        pd.concat(user_metrics_buffer)
        .groupby('date')['users']
        .sum()
        .reset_index()
    )
    user_metrics_df['platform'] = platform

    top_users_df = (
        pd.concat(top_users_buffer)
        .sort_values('user_followers', ascending=False)
        .groupby('date')
        .head(10)
        .reset_index(drop=True)
    )
    top_users_df['rank'] = (
        top_users_df.groupby('date')['user_followers']
        .rank(method='first', ascending=False)
        .astype(int)
    )
    top_users_df['platform'] = platform

    dqs_df = (
        pd.concat(dqs_buffer)
        .groupby('date')
        .sum()
        .reset_index()
    )
    dqs_df['dqs'] = (dqs_df['non_null'] / dqs_df['total'] * 100).round(2)
    dqs_df['platform'] = platform
    dqs_df = dqs_df[['date', 'platform', 'dqs']]

    if not user_metrics_df.empty:
        wr.s3.to_parquet(df=user_metrics_df, path=f"{gold_path}user_metrics/", dataset=True,  mode='append', partition_cols=['platform', 'date'])
    if not top_users_df.empty:
        wr.s3.to_parquet(df=top_users_df, path=f"{gold_path}top_users/", dataset=True, mode='append', partition_cols=['platform', 'date'])
    if not dqs_df.empty:
        wr.s3.to_parquet(df=dqs_df, path=f"{gold_path}KPI/", dataset=True, mode='append', partition_cols=['platform', 'date'])

    return {"statusCode": 200, "body": f"X: Gold layer written for {user_metrics_df.shape[0]} dates."}