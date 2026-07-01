import pandas as pd
import awswrangler as wr
import os
from urllib.parse import unquote_plus
import pg8000.native

DB_USER = os.environ['DB_USER']
DB_PASS = os.environ['DB_PASSWORD']
DB_HOST = os.environ['DB_HOST']
DB_NAME = os.environ['DB_NAME']

TABLE_MAP = {
    "bottom_users": "Bottom_Users",
    "top_users": "Top_Users",
    "post_metrics": "Post_Metrics",
    "top_posts": "Top_Posts",
    "top_jobs": "Top_Posts",
    "user_metrics": "User_Metrics",
    "KPI": "KPI"
}

TABLE_COLS = {
    "Post_Metrics":  ["stories", "comments", "jobs", "polls", "platform", "date"],
    "Top_Posts":     ["post_id", "author_username", "content_text", "created_at",
                      "post_type", "score", "year", "month", "day", "rank", "platform", "date"],
    "Top_Users":     ["username", "karma_score", "is_verified", "created_at",
                      "user_followers", "rank", "platform", "date"],
    "Bottom_Users":  ["username", "karma_score", "is_verified", "created_at",
                      "user_followers", "rank", "platform", "date"],
    "User_Metrics":  ["users", "platform", "date"],
    "KPI":           ["dqs", "platform", "date"],
}

PK_MAP = {
    "Post_Metrics":  '("platform", "date")',
    "Top_Posts":     '("platform", "date", "rank")',
    "Top_Users":     '("platform", "date", "rank")',
    "Bottom_Users":  '("platform", "date", "rank")',
    "User_Metrics":  '("platform", "date")',
    "KPI":           '("platform", "date")',
}


def lambda_handler(event, context):
    try:
        bucket  = event['Records'][0]['s3']['bucket']['name']
        raw_key = event['Records'][0]['s3']['object']['key']
        key     = unquote_plus(raw_key)
        s3_path = f"s3://{bucket}/{key}"

        table_name = None
        for k, v in TABLE_MAP.items():
            if k in key:
                table_name = v
                break
        if not table_name:
            print(f"No table mapping for key: {key}")
            return

        platform_name = "Hacker News" if "Hacker News" in key else "X"
        date_val      = key.split('date=')[1].split('/')[0]
        platform_id   = 1 if platform_name == "Hacker News" else 2
        date_id       = int(date_val.replace('-', ''))

        df = wr.s3.read_parquet(s3_path)

        target_cols = TABLE_COLS.get(table_name, [])
        df['platform'] = platform_id
        df['date']     = date_id
        valid_cols = [c for c in target_cols if c in df.columns]
        df_filtered = df[valid_cols]

        print(f"Writing {len(df_filtered)} rows to {table_name} cols={valid_cols}")

        conn = pg8000.native.Connection(
            user=DB_USER, password=DB_PASS, host=DB_HOST,
            database=DB_NAME, port=5432
        )
        try:
            # Upsert Platform/Date (ON CONFLICT avoids race conditions)
            conn.run('INSERT INTO public."Platform" (platform_id, platform_name) VALUES (:id, :p) ON CONFLICT (platform_id) DO NOTHING',
                     id=platform_id, p=platform_name)
            conn.run('INSERT INTO public."Date" (date_id, "date") VALUES (:id, :d) ON CONFLICT (date_id) DO NOTHING',
                     id=date_id, d=date_val)

            quoted = ','.join(f'"{c}"' for c in valid_cols)
            params = ','.join(f':{c}' for c in valid_cols)
            insert_sql = f'INSERT INTO public."{table_name}" ({quoted}) VALUES ({params})'

            pk = PK_MAP.get(table_name)
            if pk:
                insert_sql += f" ON CONFLICT {pk} DO NOTHING"

            for _, row in df_filtered.iterrows():
                vals = {}
                for c in valid_cols:
                    val = row[c]
                    if pd.isna(val):
                        vals[c] = None
                    else:
                        v = val.item() if hasattr(val, 'item') else val
                        if isinstance(v, float) and v == int(v):
                            v = int(v)
                        vals[c] = v
                conn.run(insert_sql, **vals)

            print(f"Done: {len(df_filtered)} rows -> {table_name}")

        finally:
            conn.close()

    except Exception as e:
        print(f"Error: {e}")
        raise