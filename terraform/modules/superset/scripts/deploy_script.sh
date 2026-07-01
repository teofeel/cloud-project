#!/bin/bash
dnf update -y
dnf install docker -y
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-use

curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

cat <<'EOF' > /home/ec2-user/schema.sql
${DDL_SCHEMA}
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
      PYTHONPATH: "/app/superset_home/.local/lib/python3.10/site-packages:/app/.venv/lib/python3.10/site-packages"
    volumes:
      - superset_home:/app/superset_home
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
    ports:
      - "8088:8088"
    volumes:
      - superset_home:/app/superset_home
    command: >
      /bin/sh -c "
      superset run -h 0.0.0.0 -p 8088 --with-threads --reload --debugger
      "

volumes:
  superset_postgres_data:
  superset_home:
EOF

chown ec2-user:ec2-user /home/ec2-user/schema.sql /home/ec2-user/docker-compose.yaml

cd /home/ec2-user
sudo docker-compose up -d

echo "Waiting for Superset..."
sleep 20

echo "Applying DDL..."

docker cp /home/ec2-user/schema.sql superset_postgres:/tmp/schema.sql
sudo docker-compose exec -T postgres psql -U admin -d superset -f /tmp/schema.sql

echo "Installing pg8000..."
sudo docker exec -u root superset_app pip install psycopg2-binary pg8000
sudo docker restart superset_app

echo "Done."