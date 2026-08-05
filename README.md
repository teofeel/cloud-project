# Social Media Analytics Pipeline on AWS

<div align="center">

[![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Python](https://img.shields.io/badge/Python-3.13-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![Apache Superset](https://img.shields.io/badge/Apache%20Superset-20A39E?style=for-the-badge&logo=apache-superset&logoColor=white)](https://superset.apache.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)

</div>

---

A fully serverless ETL pipeline that ingests social media data from **Hacker News** and **X (Twitter)**, processes it through a three-layer **medallion architecture** on Amazon S3, loads analytical results into PostgreSQL, and exposes dashboards via **Apache Superset** — all provisioned with **Terraform** on AWS.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
  - [High-Level Diagram](#high-level-diagram)
  - [Data Flow](#data-flow)
  - [Medallion Architecture](#medallion-architecture)
- [Technology Stack](#technology-stack)
- [Project Structure](#project-structure)
- [Infrastructure](#infrastructure)
  - [Network](#network)
  - [Compute Resources](#compute-resources)
  - [Storage Resources](#storage-resources)
  - [Messaging and Events](#messaging-and-events)
  - [Security & IAM](#security-iam)
- [Application Flow](#application-flow)
  - [Step-by-Step Pipeline Execution](#step-by-step-pipeline-execution)
  - [Failure Handling](#failure-handling)
- [Database Schema](#database-schema)
- [Deployment](#deployment)
  - [Prerequisites](#prerequisites)
  - [Deployment Order](#deployment-order)
  - [Required Variables](#required-variables)
- [Local Development](#local-development)
- [Monitoring & Logging](#monitoring-logging)
- [Security](#security)
- [Scalability](#scalability)

---

## Overview

This project implements a **cloud-native data pipeline** that collects, processes, and visualizes social media content. It ingests posts and user data from two distinct platforms — Hacker News (technology-focused link aggregator) and X/Twitter (Bitcoin-related tweets via Kaggle) — then transforms and enriches the raw data through a staged pipeline into actionable analytics.

**Business problem**: Organizations need a centralized, automated way to ingest multi-platform social media data, measure content quality (DQS — Data Quality Score), rank top content and users, and visualize trends over time — without managing servers.

**Solution**: A fully automated, event-driven serverless pipeline on AWS that runs daily, scales to zero between executions, and surfaces insights through Apache Superset dashboards.

---

## Features

- **Multi-source ingestion** — Collects data from Hacker News (Algolia API) and X/Twitter (Kaggle Bitcoin tweets dataset) on independent daily schedules
- **Medallion architecture** — Three-layer S3 data lake: Bronze (raw), Silver (normalized Parquet), Gold (aggregated analytics)
- **Data Quality Scoring (DQS)** — Computes completeness percentage for each platform's daily batch
- **Top/Bottom ranking** — Ranks top 10 users and top 10 posts per platform per day
- **Post type breakdown** — Classifies Hacker News content into stories, comments, jobs, and polls
- **Event-driven orchestration** — S3 triggers chain Lambda functions through the pipeline; success destinations auto-invoke downstream processing
- **Failure notifications** — SNS + SQS + Lambda fan-out delivers failure alerts to a Discord channel with CloudWatch log links
- **Analytics database** — PostgreSQL with a star-schema model (Platform, Date dimension tables + fact/metric tables)
- **Dashboards** — Apache Superset deployed via Docker Compose on EC2 for data exploration and visualization
- **Infrastructure as Code** — 100% Terraform-provisioned with modular, reusable components
- **VPC isolation** — All Lambda functions run inside private subnets with strict security group egress rules
- **Least-privilege IAM** — Role-per-pipeline-stage with scoped S3 access policies

---

## Architecture

### High-Level Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              EVENTBRIDGE (CRON)                              │
│  ┌──────────────────────────┐       ┌──────────────────────────────────┐     │
│  │ hacker-news-daily-rule   │       │ twitter-collector-daily-rule     │     │
│  │ cron(0 1 * * ? *)        │       │ cron(0 0 2 * ? *)                │     │
│  └────────────┬─────────────┘       └───────────────┬──────────────────┘     │
└───────────────┼─────────────────────────────────────┼────────────────────────┘
                │                                     │
                ▼                                     ▼
┌───────────────────────────────┐   ┌─────────────────────────────────────────┐
│  hacker_news_lambda           │   │  twitter_lambda                         │
│  • Fetches HN Algolia API     │   │  • Downloads Kaggle dataset             │
│  • Paginates 24h window       │   │  • Multipart upload to S3               │
│  • Writes raw JSON            │   │  • Writes raw CSV                       │
└───────────────┬───────────────┘   └───────────────────┬─────────────────────┘
                │                                       │
                ▼                                       ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                          BRONZE LAYER (S3)                                    │
│  s3-bronze-layer-cloud-2026                                                   │
│  ├── hn_raw_<timestamp>.json                                                  │
│  └── bronze/x_twitter/bitcoin_tweets.csv                                      │
└───────────────────────┬───────────────────────────────────────────────────────┘
                        │ S3:ObjectCreated event
                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│  normalize_hn_lambda                    normalize_x_lambda                    │
│  • JSON → DataFrame                     • CSV → DataFrame (chunked)           │
│  • Extracts users + posts               • Extracts users + posts              │
│  • Deduplicates                         • Deduplicates                        │
│  • Writes Parquet (dataset mode)        • Writes Parquet (dataset mode)       │
└───────────────────────┬───────────────────────────────────────────────────────┘
                        │ Lambda destination: on_success
                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                           SILVER LAYER (S3)                                   │
│  s3-silver-layer-cloud-2026                                                   │
│  ├── silver/users/platform=Hacker News/                                       │
│  ├── silver/users/platform=X/                                                 │
│  └── silver/posts/year=YYYY/month=MM/day=DD/                                  │
└───────────────────────┬───────────────────────────────────────────────────────┘
                        │ Lambda destination: on_success
                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│  transform_hn_lambda                    transform_x_lambda                    │
│  • Computes post_metrics                • Computes user_metrics               │
│  • Ranks top_posts, top_jobs            • Ranks top_users                     │
│  • Ranks top/bottom users              • Computes DQS                         │
│  • Computes user_metrics, DQS           • Writes Parquet (dataset mode)       │
│  • Writes Parquet (dataset mode)        • KPI, user_metrics, top_users        │
│  • KPI, post_metrics, top_posts,                                              │
│    top_jobs, top_users, bottom_users                                          │
└───────────────────────┬───────────────────────────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                            GOLD LAYER (S3)                                    │
│  s3-gold-layer-cloud-2026                                                     │
│  ├── gold/KPI/                                                                │
│  ├── gold/post_metrics/                                                       │
│  ├── gold/top_posts/                                                          │
│  ├── gold/top_jobs/                                                           │
│  ├── gold/top_users/                                                          │
│  ├── gold/bottom_users/                                                       │
│  └── gold/user_metrics/                                                       │
└───────────────────────┬───────────────────────────────────────────────────────┘
                        │ S3:ObjectCreated event
                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│  injector_lambda                                                              │
│  • Reads Parquet from Gold                                                    │
│  • Upserts into PostgreSQL (Platform, Date dims + fact tables)                │
│  • Uses ON CONFLICT DO NOTHING for idempotency                                │
└───────────────────────┬───────────────────────────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                    EC2: visualization-instance (t3.micro)                     │
│  ┌─────────────────────────────────────────┐                                  │
│  │  Docker Compose                         │                                  │
│  │  ├── superset_app (port 8088)           │  Apache Superset dashboards      │
│  │  └── superset_postgres (port 5432)      │  Analytics + metadata DB         │
│  └─────────────────────────────────────────┘                                  │
└───────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────────┐
│                         FAILURE HANDLING                                      │
│  Any Lambda failure ──► SNS (job-failures) ──► SQS (job-failures-queue)       │
│                                                  │                            │
│                                                  ▼                            │
│                                        discord_notifier_lambda                │
│                                        • Parses failure event                 │
│                                        • Sends alert to Discord webhook       │
│                                        • Includes CloudWatch + Lambda links   │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

| Stage | Source | Transform | Destination | Trigger |
|-------|--------|-----------|-------------|---------|
| **Ingest** | HN API / Kaggle | Raw JSON / CSV | Bronze S3 | EventBridge cron |
| **Normalize** | Bronze S3 | Clean, deduplicate, structure | Silver S3 (Parquet) | S3 ObjectCreated |
| **Transform** | Silver S3 | Aggregate, rank, score | Gold S3 (Parquet) | Lambda destination (on_success) |
| **Inject** | Gold S3 | Map to tables, upsert | PostgreSQL | S3 ObjectCreated |
| **Visualize** | PostgreSQL | — | Superset dashboards | Manual / on-demand |

### Medallion Architecture

| Layer | Format | Partitioning | Contents |
|-------|--------|-------------|----------|
| **Bronze** | JSON / CSV | None | Raw ingested data, immutable |
| **Silver** | Parquet | `platform`, `year`/`month`/`day` | Cleaned, deduplicated users & posts |
| **Gold** | Parquet | `platform`, `date` | Aggregated KPIs, rankings, metrics |

---

## Technology Stack

### Cloud
| Category | Technology |
|----------|-----------|
| **Cloud Provider** | AWS (eu-west-1) |
| **IaC** | Terraform ~> 1.6 (HashiCorp AWS Provider ~> 6.0) |

### Compute
| Category | Technology |
|----------|-----------|
| **Serverless** | AWS Lambda (Python 3.13) |
| **Scheduling** | Amazon EventBridge (cron expressions) |
| **Virtual Machines** | EC2 t3.micro (Amazon Linux 2023) |

### Storage
| Category | Technology |
|----------|-----------|
| **Data Lake** | Amazon S3 (SSE-AES256 encryption, versioning enabled) |
| **Database** | PostgreSQL 15 (Docker on EC2) |

### Messaging & Events
| Category | Technology |
|----------|-----------|
| **Pub/Sub** | Amazon SNS |
| **Queue** | Amazon SQS (standard queue, SSE enabled) |
| **Event Bus** | Amazon EventBridge |

### Networking
| Category | Technology |
|----------|-----------|
| **VPC** | Custom VPC (10.0.0.0/16) |
| **NAT** | fck-nat AMI (t3.micro EC2) |
| **Private Connectivity** | S3 Gateway VPC Endpoint |

### Data Processing
| Category | Technology |
|----------|-----------|
| **Data Wrangling** | Pandas, AWS Data Wrangler (`awswrangler`) |
| **Formats** | JSON, CSV, Parquet |

### Visualization
| Category | Technology |
|----------|-----------|
| **BI Platform** | Apache Superset (latest) |
| **Container Runtime** | Docker + Docker Compose |

### Languages
| Language | Usage |
|----------|-------|
| **Python 3.13** | All Lambda functions |
| **HCL (HashiCorp)** | All Terraform infrastructure |
| **Bash** | EC2 user-data bootstrap script |
| **SQL** | PostgreSQL DDL (star schema) |

### External Data Sources
| Source | Method |
|--------|--------|
| **Hacker News** | Algolia Search API (public) |
| **X / Twitter** | Kaggle dataset: `kaushiksuresh147/bitcoin-tweets` |

---

## Project Structure

```
cloud-project/
│
├── code/                                   # Lambda function source code
│   ├── hacker_news_lambda.py               # Collector: HN API → Bronze S3
│   ├── twitter_lambda.py                   # Collector: Kaggle → Bronze S3
│   ├── normalize_hn_lambda.py              # Normalizer: Bronze JSON → Silver Parquet
│   ├── normalize_x_lambda.py               # Normalizer: Bronze CSV → Silver Parquet
│   ├── transform_hn_lambda.py              # Transformer: Silver → Gold (HN metrics)
│   ├── transform_x_lambda.py               # Transformer: Silver → Gold (X metrics)
│   ├── injector_lambda.py                  # Injector: Gold Parquet → PostgreSQL
│   └── discord_notifier_lambda.py          # Notifier: SQS → Discord webhook
│
├── terraform/                              # Infrastructure as Code
│   ├── envs/dev/                           # Development environment
│   │   ├── main.tf                         # Root module: wires everything together
│   │   ├── variables.tf                    # Input variable declarations
│   │   └── terraform.tfvars                # Variable values (public config)
│   │
│   ├── global/iam/                         # Global IAM (cross-environment)
│   │   ├── main.tf                         # IAM users, groups, roles, policies
│   │   ├── variables.tf                    # IAM-specific variables
│   │   ├── outputs.tf                      # Exported role ARNs and names
│   │   └── terraform.tfvars               # Admin user list
│   │
│   └── modules/                            # Reusable Terraform modules
│       ├── vpc/                            # VPC + subnets + route tables + IGW
│       ├── lambda/                         # Lambda function + IAM policy attachment
│       ├── s3/                             # S3 bucket + encryption + versioning
│       ├── security_groups/                # Dynamic security group builder
│       ├── eventbridge/                    # EventBridge rule + Lambda target
│       ├── sqs/                            # SQS standard queue
│       ├── sns/                            # SNS topic + subscription
│       ├── gateway_endpoint/               # VPC Gateway/Interface endpoints
│       └── superset/                       # EC2 + Superset Docker Compose
│           └── scripts/
│               ├── deploy_script.sh        # EC2 user-data bootstrap
│               ├── docker-compose.yaml     # Superset + PostgreSQL compose
│               ├── superset_config.py      # Superset configuration
│               ├── cloud-ddl.sql           # PostgreSQL schema (star schema)
│               └── cloud_projekat.pub      # SSH public key for EC2 access
│
└── .gitignore                              # Git ignore rules
```

---

## Infrastructure

### Network

| Resource | Configuration | Purpose |
|----------|--------------|---------|
| **VPC** | `10.0.0.0/16` | Network isolation for all resources |
| **Public Subnet** | `10.0.1.0/24` | NAT instance, Superset EC2 |
| **Private Subnet** | `10.0.2.0/24` | All Lambda functions |
| **Internet Gateway** | Attached to VPC | Public internet access for public subnet |
| **Public Route Table** | `0.0.0.0/0` → IGW | Routes public subnet traffic to internet |
| **Private Route Table** | `0.0.0.0/0` → fck-nat ENI | Routes private Lambda traffic through NAT |
| **S3 Gateway Endpoint** | `com.amazonaws.eu-west-1.s3` | Private S3 access without internet traversal |
| **fck-nat** | `t3.micro` EC2 | Cost-effective NAT for private subnets |

### Compute Resources

| Resource | Runtime | Memory | Timeout | Storage | VPC |
|----------|---------|--------|---------|---------|-----|
| **hacker_news_lambda** | Python 3.13 | 3008 MB | 900s | 10 GB ephemeral | Private subnet |
| **twitter_lambda** | Python 3.13 | 3008 MB | 900s | 10 GB ephemeral | Private subnet |
| **normalize_hn_lambda** | Python 3.13 | 3008 MB | 900s | 10 GB ephemeral | Private subnet |
| **normalize_x_lambda** | Python 3.13 | 3008 MB | 900s | 10 GB ephemeral | Private subnet |
| **transform_hn_lambda** | Python 3.13 | 3008 MB | 900s | 10 GB ephemeral | Private subnet |
| **transform_x_lambda** | Python 3.13 | 3008 MB | 900s | 10 GB ephemeral | Private subnet |
| **injector_lambda** | Python 3.13 | 3008 MB | 900s | 10 GB ephemeral | Private subnet |
| **discord_notifier_lambda** | Python 3.13 | 3008 MB | 900s | 10 GB ephemeral | Private subnet |
| **visualization-instance** | EC2 t3.micro | — | — | EBS root | Public subnet |

**Lambda Layers:**
- `AWSSDKPandas-Python313` (v4) — AWS Data Wrangler & Pandas for data processing
- `injector-sqlalchemy-psycopg2` — Custom layer with `pg8000` for PostgreSQL connectivity

### Storage Resources

| Bucket | Purpose | Encryption | Versioning | Public Access |
|--------|---------|-----------|------------|---------------|
| `s3-bronze-layer-cloud-2026` | Raw ingested data (JSON, CSV) | SSE-AES256 | Enabled | Fully blocked |
| `s3-silver-layer-cloud-2026` | Normalized data (Parquet) | SSE-AES256 | Enabled | Fully blocked |
| `s3-gold-layer-cloud-2026` | Aggregated analytics (Parquet) | SSE-AES256 | Enabled | Fully blocked |

### Messaging and Events

| Resource | Name | Purpose |
|----------|------|---------|
| **EventBridge Rule** | `hacker-news-collector-daily-rule` | Triggers HN collector daily at 01:00 UTC |
| **EventBridge Rule** | `twitter-collector-daily-rule` | Triggers X collector daily at 00:00 UTC on the 2nd |
| **SNS Topic** | `job-failures` | Receives all Lambda failure events |
| **SQS Queue** | `job-failures-queue` | Buffers failure events; triggers Discord notifier |

### Security & IAM

| Role | Used By | Key Policies |
|------|---------|-------------|
| **collectors-lambda-execution-role** | HN & Twitter collector Lambdas | VPC access, Bronze S3 write, SNS publish |
| **normalizer-lambda-execution-role** | Normalize HN & X Lambdas | VPC access, Bronze read + Silver write, SNS publish, Lambda invoke (transform) |
| **transform-lambda-execution-role** | Transform HN & X Lambdas | VPC access, Silver read + Gold write, SNS publish |
| **injector-lambda-execution-role** | Injector Lambda | VPC access, Gold S3 read, SNS publish |
| **discord-notifier-lambda-execution-role** | Discord notifier Lambda | VPC access, SQS receive/delete, CloudWatch Logs |
| **admin** (IAM Group) | 3 IAM users (Teodor, Isidora, Ivana) | AdministratorAccess (`*` on `*`) |

---

## Application Flow

### Step-by-Step Pipeline Execution

**1. Scheduled Collection (EventBridge)**
- `hacker_news_lambda` triggers daily at 01:00 UTC. It paginates the Algolia HN Search API in 30-minute windows, collecting up to 1,000 items per window for the past 24 hours. Results are written as a single JSON file to the Bronze S3 bucket.
- `twitter_lambda` triggers monthly (day 2 at 00:00 UTC). It authenticates with the Kaggle API, downloads the Bitcoin tweets dataset, extracts the CSV, and uploads it to Bronze S3 using multipart transfer (15 MB chunks, 20 concurrent threads).

**2. Normalization (S3 → Lambda)**
- When a `.json` file lands in the Bronze bucket, an S3 notification triggers `normalize_hn_lambda`. It reads the raw JSON, extracts user profiles and post metadata, deduplicates by username and post ID, and writes partitioned Parquet datasets to the Silver bucket (`silver/users/` and `silver/posts/`).
- `normalize_x_lambda` is triggered similarly for CSV files. It reads the large CSV in 50,000-row chunks, extracts user and post data, deduplicates, and writes to Silver as Parquet.

**3. Transformation (Lambda Destination — on_success)**
- When `normalize_hn_lambda` succeeds, AWS Lambda automatically invokes `transform_hn_lambda` via the `on_success` destination. It reads Silver Parquet, computes:
  - **Post metrics** — counts of stories, comments, jobs, polls
  - **Top 10 posts** — by score
  - **Top 10 jobs** — by score
  - **Top 10 users** — by karma
  - **Bottom 10 users** — by karma
  - **User metrics** — total unique users
  - **DQS (Data Quality Score)** — `(non-null cells / total cells) × 100`
- `transform_x_lambda` is triggered on success of the X normalizer. It reads Silver user data chunked by 50,000 rows, computes daily user metrics, top 10 users by followers, and DQS. Results are written to Gold as Parquet partitioned by platform and date.

**4. Database Injection (S3 → Lambda)**
- When `.parquet` files land in the Gold bucket, an S3 notification triggers `injector_lambda`. It maps the S3 key to a PostgreSQL table name, reads the Parquet file, and performs row-by-row upserts into the analytics database. Dimension tables (`Platform`, `Date`) are populated with `ON CONFLICT DO NOTHING` semantics. Fact tables use composite primary keys for idempotent inserts.

**5. Visualization (Apache Superset)**
- Apache Superset connects to the same PostgreSQL database. Analysts can create and view dashboards, charts, and SQL queries against the analytics tables at `http://<ec2-public-ip>:8088`.

### Failure Handling

All Lambda functions are configured with `maximum_retry_attempts = 0` (no automatic retries). Failures are routed via Lambda Destinations:

```
Lambda Failure ──► SNS Topic (job-failures) ──► SQS Queue (job-failures-queue) ──► discord_notifier_lambda ──► Discord Webhook
```

The Discord notification includes:
- Failing Lambda function name and ARN
- Error status and error message
- Deep links to the Lambda console and CloudWatch Logs for that function
- AWS region context

---

## Database Schema

The PostgreSQL database uses a **star schema** design:

```
┌──────────────┐       ┌──────────────┐
│   Platform   │       │     Date     │
│──────────────│       │──────────────│
│ platform_id  │◄──────│ date_id      │
│ platform_name│       │ date         │
└──────────────┘       └──────┬───────┘
        │                      │
        │         ┌────────────┼────────────┐
        │         │            │            │
        ▼         ▼            ▼            ▼
   ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐
   │   KPI   │ │Post_     │ │Top_      │ │Bottom_       │
   │─────────│ │Metrics   │ │Posts     │ │Users         │
   │ dqs     │ │──────────│ │──────────│ │──────────────│
   │platform │ │stories   │ │post_id   │ │username      │
   │ date    │ │comments  │ │author    │ │karma_score   │
   └─────────┘ │jobs      │ │content   │ │is_verified   │
               │polls     │ │score     │ │created_at    │
               │platform  │ │post_type │ │user_followers│
               │ date     │ │rank      │ │rank          │
               └──────────┘ │platform  │ │platform      │
                            │ date     │ │ date         │
   ┌──────────┐             └──────────┘ └──────────────┘
   │Top_Users │
   │──────────│
   │username  │             ┌──────────────┐
   │karma     │             │User_Metrics  │
   │verified  │             │──────────────│
   │created   │             │ users        │
   │followers │             │ platform     │
   │rank      │             │ date         │
   │platform  │             └──────────────┘
   │ date     │
   └──────────┘
```

---

## Deployment

### Prerequisites

- **Terraform** ≥ 1.6
- **AWS CLI** configured with credentials
- **Python 3.13** (for local Lambda testing)
- **Docker** (for local Superset testing)
- **PowerShell** (for building the injector Lambda layer on Windows)

### Deployment Order

The infrastructure must be deployed in two stages:

**Stage 1 — Global IAM**

```bash
cd terraform/global/iam
terraform init
terraform apply -var-file="terraform.tfvars"
```

This creates all IAM roles, policies, users, and the admin group. Outputs (role ARNs) are consumed by the dev environment via `terraform_remote_state`.

**Stage 2 — Development Environment**

```bash
cd terraform/envs/dev
terraform init
terraform apply -var-file="terraform.tfvars"
```

This provisions the full infrastructure:

1. VPC with public/private subnets, IGW, route tables
2. fck-nat EC2 instance
3. S3 buckets (Bronze, Silver, Gold)
4. All 8 Lambda functions with layers
5. EventBridge cron rules
6. SNS topic + SQS queue
7. S3 bucket notifications and Lambda event source mappings
8. Lambda destination configurations (on_success / on_failure)
9. Visualization EC2 instance with Superset Docker Compose

### Required Variables

Create a `secrets.tfvars` file (git-ignored) with sensitive values:

```hcl
kaggle_username = "<your-kaggle-username>"
kaggle_key      = "<your-kaggle-api-key>"
db_password     = "<postgres-password>"
discord_webhook_url = "<discord-webhook-url>"
```

Then apply with:

```bash
terraform apply -var-file="terraform.tfvars" -var-file="secrets.tfvars"
```

---

## Local Development

### Lambda Functions

Each Lambda can be tested locally by uncommenting the `if __name__ == "__main__"` block at the bottom of the Python file and running:

```bash
cd code
python normalize_hn_lambda.py
```

**Note**: Lambda functions require environment variables and AWS resources (S3 buckets, RDS) to function fully. For local testing, you may need to mock S3 events and database connections.

### Superset

The Superset stack can be run locally using the provided Docker Compose file:

```bash
cd terraform/modules/superset/scripts
docker-compose up -d
```

Superset will be available at `http://localhost:8088` (credentials: `admin` / `admin`).

---

## Configuration

| File | Purpose |
|------|---------|
| `terraform/envs/dev/terraform.tfvars` | Non-sensitive Terraform variables (bucket names, Lambda config, VPC CIDRs) |
| `terraform/envs/dev/secrets.tfvars` | Sensitive values (Kaggle credentials, DB passwords, Discord webhook) — **git-ignored** |
| `terraform/global/iam/terraform.tfvars` | Admin IAM user list |
| `terraform/modules/superset/scripts/superset_config.py` | Superset Python config (DB URI, SECRET_KEY) |
| `terraform/modules/superset/scripts/cloud-ddl.sql` | PostgreSQL DDL for analytics schema |

---

## Security

### IAM Least Privilege

Each pipeline stage has its own IAM role with permissions scoped to exactly what it needs:

- **Collectors** — Write-only to Bronze S3; no read access to Silver or Gold
- **Normalizers** — Read Bronze + Write Silver; can invoke Transform Lambdas
- **Transformers** — Read Silver + Write Gold; cannot access Bronze
- **Injector** — Read Gold; write to PostgreSQL; no S3 write access
- **Discord Notifier** — SQS receive/delete + CloudWatch Logs only

### Data at Rest

- All S3 buckets use **SSE-AES256** server-side encryption
- **S3 Versioning** is enabled on all buckets for data recovery
- **Public access is fully blocked** on all S3 buckets (all four block settings enabled)

### Network Isolation

- All Lambda functions run in **private subnets** with no direct internet access
- Outbound internet access (for HN API, Kaggle API, Discord webhook) routes through the NAT instance
- S3 access from private subnets goes through the **S3 Gateway VPC Endpoint** (does not traverse the public internet)
- Security groups follow least-privilege egress:
  - **Normalizers**: Only outbound HTTPS to S3 prefix list
  - **Transformers**: Only outbound HTTPS to S3 prefix list
  - **Notifier**: Only outbound HTTPS to `0.0.0.0/0` (required for Discord webhook)
  - **Injector**: Only outbound to PostgreSQL (5432) and S3 prefix list

### Secrets Management

Sensitive values (Kaggle API keys, database passwords, Discord webhook URL) are passed as Terraform variables marked `sensitive = true`. These are provided via a git-ignored `secrets.tfvars` file and are not stored in version control.

---

## Monitoring & Logging

### CloudWatch Logs

All Lambda functions write logs to Amazon CloudWatch Logs via the standard Lambda execution role permissions (`logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`). Log output includes:
- Record counts at each pipeline stage
- Row counts written to each table
- Error messages and stack traces on failure

### Failure Notifications

Failures are pushed to Discord in real-time via the SNS → SQS → Lambda pipeline. Each notification includes:
- Failing resource name
- Error status and message
- Deep links to Lambda console and CloudWatch Logs

### EC2 Monitoring

The visualization EC2 instance has `monitoring = true` enabled, providing CloudWatch metrics at 1-minute granularity.

### Current Limitations

- No CloudWatch Metrics or custom metrics are defined
- No CloudWatch Alarms are configured
- No CloudWatch Dashboards exist
- No structured logging format (plain `print()` statements)
- No distributed tracing

---

## Scalability

### Lambda

- **Memory**: 3,008 MB per function — sufficient for in-memory DataFrame operations on typical daily batches
- **Timeout**: 900 seconds (max) — handles large CSV processing (50k row chunks)
- **Ephemeral Storage**: 10 GB — accommodates large Kaggle dataset downloads
- **Concurrency**: Default account limits apply; pipeline is single-threaded per platform (serial execution via Lambda destinations)

### S3

- Object storage is **inherently scalable** with no practical limits for this use case
- Parquet format with partitioning enables efficient queries as data grows

### EC2 / Superset

- Single `t3.micro` instance — suitable for small-team dashboards
- Can be vertically scaled to larger instance types for more concurrent users
- PostgreSQL runs on the same instance; for production, migrate to Amazon RDS

### Bottlenecks

- The injector Lambda performs **row-by-row inserts** using a loop — this is a known bottleneck for large batches
- No parallel fan-out within a pipeline stage; each stage processes the full batch sequentially

---
