import os
 
SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "IKN+MO1nNjb5gyOjmSE3jzISQFM3F6dsZV8M9osmdLpqD5LKP32NCTQH")
 
SQLALCHEMY_DATABASE_URI = os.environ.get(
    "SQLALCHEMY_DATABASE_URI",
    "postgresql+psycopg2://superset:superset@postgres:5432/superset",
)