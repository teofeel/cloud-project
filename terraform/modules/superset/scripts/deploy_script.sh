#!/bin/bash
set -euo pipefail

dnf update -y
dnf install docker -y

fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

mkdir -p /home/ec2-user/superset_config

cat <<'EOF' > /home/ec2-user/schema.sql
${DDL_SCHEMA}
EOF

cat <<'EOF' > /home/ec2-user/superset_config/superset_config.py
import os

SQLALCHEMY_DATABASE_URI = os.environ.get("SQLALCHEMY_DATABASE_URI")
SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY")
EOF

cat <<'EOF' > /home/ec2-user/docker-compose.yaml
version: "3.8"

x-superset-image: &superset-image apache/superset:latest

services:
  postgres:
    image: postgres:15
    container_name: superset_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: superset
    volumes:
      - superset_postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin"]
      interval: 5s
      timeout: 5s
      retries: 10

  superset-init:
    image: *superset-image
    container_name: superset_init
    depends_on:
      postgres:
        condition: service_healthy
    environment: &superset-env
      SUPERSET_SECRET_KEY: "IKN+MO1nNjb5gyOjmSE3jzISQFM3F6dsZV8M9osmdLpqD5LKP32NCTQH"
      SQLALCHEMY_DATABASE_URI: "postgresql+psycopg2://admin:${DB_PASSWORD}@postgres:5432/superset"
      PYTHONPATH: "/app/pythonpath:/app/superset_home/.local/lib/python3.10/site-packages:/app/.venv/lib/python3.10/site-packages"
    volumes:
      - superset_home:/app/superset_home
      - /home/ec2-user/superset_config/superset_config.py:/app/pythonpath/superset_config.py
    entrypoint: /bin/sh
    command: >
      -c "
      superset db upgrade &&
      superset fab create-admin --username admin --firstname Admin --lastname Admin --email admin@admin.com --password admin &&
      superset init
      "
    restart: "no"

  superset:
    image: *superset-image
    container_name: superset_app
    restart: unless-stopped
    depends_on:
      - superset-init
    environment: *superset-env
    volumes:
      - superset_home:/app/superset_home
      - /home/ec2-user/superset_config/superset_config.py:/app/pythonpath/superset_config.py
    ports:
      - "8088:8088"
    command: >
      /bin/sh -c "
      superset run -h 0.0.0.0 -p 8088 --with-threads --reload --debugger
      "

volumes:
  superset_postgres_data:
  superset_home:
EOF

chown -R ec2-user:ec2-user /home/ec2-user/schema.sql /home/ec2-user/docker-compose.yaml /home/ec2-user/superset_config

echo "Pre-installing psycopg2-binary..."
sudo docker pull apache/superset:latest
sudo docker volume create ec2-user_superset_home 2>/dev/null || true
sudo docker run --rm \
  -v ec2-user_superset_home:/app/superset_home \
  apache/superset:latest \
  pip install --target /app/superset_home/.local/lib/python3.10/site-packages psycopg2-binary

cd /home/ec2-user
sudo docker-compose up -d

echo "Waiting for superset-init to finish (PostgreSQL migrations, should be fast)..."
EXIT_CODE=$(sudo docker wait superset_init)
if [ "$EXIT_CODE" != "0" ]; then
  echo "superset-init failed with exit code $EXIT_CODE"
  sudo docker logs superset_init
  exit 1
fi
echo "superset-init completed successfully."

echo "Applying DDL..."
sudo docker cp /home/ec2-user/schema.sql superset_postgres:/tmp/schema.sql
sudo docker-compose exec -T postgres psql -U admin -d superset -f /tmp/schema.sql

echo "Installing pg8000..."
sudo docker exec -u root superset_app pip install psycopg2-binary pg8000
sudo docker restart superset_app


echo "Done"