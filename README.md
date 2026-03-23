# 🚀 AWS Daily Resource Monitor

<div align="center">

![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Bash](https://img.shields.io/badge/bash-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Amazon S3](https://img.shields.io/badge/Amazon%20S3-FF9900?style=for-the-badge&logo=amazons3&logoColor=white)
![Amazon SES](https://img.shields.io/badge/Amazon%20SES-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)

**A fully automated AWS infrastructure auditing system that collects resource inventories across 14 AWS services, stores logs in S3, and delivers daily email reports via Amazon SES — all powered by a single Bash script and Linux cron.**

[Features](#-features) · [Architecture](#-architecture) · [Quick Start](#-quick-start) · [Installation](#-installation) · [Configuration](#-configuration) · [Usage](#-usage) · [Troubleshooting](#-troubleshooting)

</div>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Architecture](#-architecture)
- [AWS Services Monitored](#-aws-services-monitored)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [IAM Setup](#-iam-setup)
- [SES Setup](#-ses-setup)
- [S3 Setup](#-s3-setup)
- [Usage](#-usage)
- [Cron Scheduling](#-cron-scheduling)
- [Log Structure](#-log-structure)
- [Project Structure](#-project-structure)
- [Troubleshooting](#-troubleshooting)

---

## 🔍 Overview

**AWS Daily Resource Monitor** is a lightweight, zero-dependency DevOps automation tool built entirely in Bash. Every day at 5:00 PM, it automatically:

1. **Collects** resource inventories from 14 AWS services in a single sweep
2. **Saves** all output into a timestamped, structured log file
3. **Uploads** the log to a private Amazon S3 bucket
4. **Generates** a secure pre-signed download URL (valid for 7 days)
5. **Emails** you the download link via Amazon SES

No agents. No third-party tools. No dashboards to maintain. Just AWS CLI + Bash + Cron.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔄 **Fully Automated** | Runs daily at 5 PM via Linux cron, zero manual intervention |
| 📊 **14 Services** | Covers all major AWS infrastructure services in one report |
| 📁 **Structured Logs** | Human-readable, timestamped, section-divided log files |
| ☁️ **S3 Storage** | Logs stored securely in private S3 with 7-day presigned URLs |
| 📧 **Email Delivery** | Daily email via SES with direct download link |
| 🔐 **Least Privilege IAM** | Minimal, read-only permissions — principle of least privilege |
| 🧹 **Auto Cleanup** | Automatically purges local logs older than 30 days |
| 🧪 **Manually Testable** | Run the main script at any time without waiting for cron |
| 🪶 **Zero Dependencies** | Only requires AWS CLI — no Python, Node, or extra packages |
| 📋 **Easy Config** | Single config block at the top of the script |

---

## 🏗️ Architecture

![Architecture Diagram](docs/ARCHITECTURE.png)

---

## 🛠️ AWS Services Monitored

| # | Service | Resources Collected |
|---|---------|-------------------|
| 1 | **EC2** | Instances (ID, type, state, IPs, name), Security Groups |
| 2 | **RDS** | DB instances (identifier, class, engine, status, endpoint) |
| 3 | **S3** | All buckets with creation dates, total count |
| 4 | **CloudFront** | Distributions (ID, domain, status, origin) |
| 5 | **VPC** | VPCs (ID, CIDR, state, default flag), Subnets |
| 6 | **IAM** | Users, Roles, Groups (name, ID, creation date) |
| 7 | **Route 53** | Hosted zones (name, ID, type, record count) |
| 8 | **CloudWatch** | Alarms (name, state, metric), Log Groups |
| 9 | **CloudFormation** | Active stacks (name, status, creation time) |
| 10 | **Lambda** | Functions (name, runtime, memory, timeout, last modified) |
| 11 | **SNS** | Topics list, Subscriptions (topic, protocol, endpoint) |
| 12 | **SQS** | Queue URLs |
| 13 | **DynamoDB** | Tables list + per-table details (status, items, size, capacity) |
| 14 | **EBS** | Volumes (ID, size, type, state, AZ, attached instance), Snapshots |

---

## 📦 Prerequisites

Before you begin, ensure you have:

- [ ] An **AWS Account** with access to the console
- [ ] A **Linux EC2 instance** (Amazon Linux 2 / Ubuntu 20.04+) running
- [ ] **SSH access** to your EC2 instance
- [ ] An **email address** you can verify in SES
- [ ] About **30–60 minutes** for initial setup

---

## ⚡ Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/sumzbiz/aws-daily-resource-monitor.git
cd aws-daily-resource-monitor

# 2. Run the setup script (installs AWS CLI, creates directories)
chmod +x scripts/setup.sh
./scripts/setup.sh

# 3. Edit the configuration
nano scripts/aws_resource_monitor.sh
# → Update S3_BUCKET, AWS_REGION, SENDER_EMAIL, RECIPIENT_EMAIL

# 4. Make it executable
chmod +x scripts/aws_resource_monitor.sh

# 5. Test manually
bash scripts/aws_resource_monitor.sh

# 6. Schedule with cron
crontab -e
# → Add the cron line from the Cron Scheduling section
```

---

## 🔧 Installation

### Step 1: Clone the Repository

```bash
git clone https://github.com/sumzbiz/aws-daily-resource-monitor.git
cd aws-daily-resource-monitor
```

### Step 2: Run Automated Setup

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

The setup script will:
- Check if AWS CLI is installed (and install it if not)
- Create the required directory structure
- Verify your AWS credentials
- Prompt you to confirm your configuration

### Step 3: Configure AWS CLI

```bash
aws configure
```

Enter your credentials when prompted:
```
AWS Access Key ID:     
AWS Secret Access Key: 
Default region name:   
Default output format: json
```

### Step 4: Verify Setup

```bash
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDA...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/aws-resource-monitor"
}
```

---

## ⚙️ Configuration

Open the script and update the configuration block at the top:

```bash
nano scripts/aws_resource_monitor.sh
```

```bash
# ─── CONFIGURATION BLOCK ────────────────────────────────────
S3_BUCKET="your-unique-bucket-name"        # Your S3 bucket name
AWS_REGION="us-east-1"                     # Your AWS region
SENDER_EMAIL="you@example.com"             # SES-verified sender email
RECIPIENT_EMAIL="you@example.com"          # SES-verified recipient email
PRESIGN_EXPIRY_SECONDS=604800              # Link validity (default: 7 days)
LOG_DIR="/home/ec2-user/aws-monitor/logs"  # Local log storage path
# ────────────────────────────────────────────────────────────
```

> ⚠️ **Important:** If your Linux username is not `ec2-user`, update the `LOG_DIR` path accordingly.
> - Amazon Linux: `/home/ec2-user/`
> - Ubuntu: `/home/ubuntu/`

---

## 🔐 IAM Setup

### Create the IAM User

1. AWS Console → **IAM** → **Users** → **Create user**
2. Username: `aws-resource-monitor`
3. Select **"Attach policies directly"** → **"Create policy"**
4. Paste the JSON from `iam/policy.json` (see below)
5. Policy name: `AWSResourceMonitorPolicy`
6. Attach policy to user → Create user
7. Create **Access Keys** → Save securely → Run `aws configure`

### IAM Policy

The full policy is in [`iam/policy.json`](iam/policy.json).

Key permissions granted (all **read-only** except S3 upload and SES send):

```
EC2:   Describe* (instances, VPCs, subnets, security groups, volumes)
RDS:   Describe* (DB instances, clusters, snapshots)
S3:    ListAllMyBuckets + PutObject (upload only to your bucket)
IAM:   List* (users, roles, groups, policies)
SES:   SendEmail, SendRawEmail
...and more — see iam/policy.json for full details
```

> ⚠️ After creating your S3 bucket, update `iam/policy.json` — replace `YOUR-BUCKET-NAME` with your real bucket name before applying.

---

## 📧 SES Setup

### Verify Your Email

1. AWS Console → **SES** → **Verified identities**
2. Click **"Create identity"** → Select **"Email address"**
3. Enter your email → Click **"Create identity"**
4. Check your inbox → Click the verification link
5. Return to SES — status should show ✅ **Verified**

### Sandbox Mode Note

> ⚠️ New AWS accounts start in **SES Sandbox mode**.
> In sandbox mode, **both sender and recipient emails must be verified**.
> For personal use, simply verify the same email as both sender and recipient.
> To send to any email address, [request production access](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html) from AWS.

### Test SES Manually

```bash
aws ses send-email \
  --from "your@email.com" \
  --to "your@email.com" \
  --subject "SES Test from AWS Monitor" \
  --text "SES is working correctly!" \
  --region us-east-1
```

---

## 🪣 S3 Setup

### Create the Bucket

```bash
# Replace with your unique bucket name and region
aws s3 mb s3://your-unique-bucket-name --region us-east-1
```

Or via AWS Console:
1. **S3** → **Create bucket**
2. Name: `aws-resource-logs-yourname-2024` (must be globally unique)
3. Region: Same as your AWS CLI config
4. Keep **"Block all public access"** enabled ✅
5. Click **"Create bucket"**

### Verify Upload Works

```bash
echo "test" > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://YOUR-BUCKET-NAME/test.txt
aws s3 ls s3://YOUR-BUCKET-NAME/
```

---

## 🚀 Usage

### Run Manually (Test)

```bash
bash scripts/aws_resource_monitor.sh
```

### View Generated Logs

```bash
# List all log files
ls -lht ~/aws-monitor/logs/

# View the latest log
cat $(ls -t ~/aws-monitor/logs/aws-resources-*.log | head -1)

# Page through a large log
less $(ls -t ~/aws-monitor/logs/aws-resources-*.log | head -1)

# Search within a log
grep "EC2" $(ls -t ~/aws-monitor/logs/aws-resources-*.log | head -1)
```

### View Files in S3

```bash
# List all uploaded reports
aws s3 ls s3://YOUR-BUCKET-NAME/daily-reports/

# Download a specific report
aws s3 cp s3://YOUR-BUCKET-NAME/daily-reports/aws-resources-2024-01-15_17-00-00.log ./
```

### Check Cron Output Log

```bash
# See what cron output was (errors, success messages)
cat ~/aws-monitor/logs/cron_output.log
```

---

## ⏰ Cron Scheduling

### Add to Crontab

```bash
crontab -e
```

Add the following **two lines** (the PATH line is required):

```cron
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

0 17 * * * /bin/bash /home/ec2-user/aws-monitor/scripts/aws_resource_monitor.sh >> /home/ec2-user/aws-monitor/logs/cron_output.log 2>&1
```

> **Time format explanation:**
> - `0` → at minute 0
> - `17` → at hour 17 (5 PM)
> - `* * *` → every day, every month, every day of the week

### Verify Cron Entry

```bash
crontab -l
```

### Test Cron is Running

```bash
# Check cron service status
sudo systemctl status cron        # Ubuntu
sudo systemctl status crond       # Amazon Linux
```

### Change the Schedule

| Schedule | Cron Expression |
|----------|----------------|
| Daily at 5 PM | `0 17 * * *` |
| Daily at 8 AM | `0 8 * * *` |
| Every Monday at 9 AM | `0 9 * * 1` |
| Every 12 hours | `0 */12 * * *` |
| Every hour | `0 * * * *` |

---

## 📄 Log Structure

Each log file follows this structure:

```
==========================================
  AWS DAILY RESOURCE REPORT
  Generated: January 15, 2024 at 05:00 PM
==========================================

Report Date  : January 15, 2024 at 05:00 PM
Region       : us-east-1
Log File     : /home/ec2-user/aws-monitor/logs/aws-resources-2024-01-15_17-00-00.log

------------------------------------------
  >>> EC2 - INSTANCES
------------------------------------------
[table output]

------------------------------------------
  >>> RDS - DATABASE INSTANCES
------------------------------------------
[table output]

... (all 14 services)

==========================================
  END OF REPORT
  Completed: January 15, 2024 at 05:02 PM
==========================================
```

Log files are named: `aws-resources-YYYY-MM-DD_HH-MM-SS.log`

---

## 📁 Project Structure

```
aws-daily-resource-monitor/
│
├── 📄 README.md                          ← You are here
├── 📄 .gitignore                         ← Git ignore rules
│
├── 📂 scripts/
│   ├── 🔧 aws_resource_monitor.sh        ← Main automation script
│   └── 🔧 setup.sh                       ← One-time setup script
│
├── 📂 iam/
│   └── 📋 policy.json                    ← Least-privilege IAM policy
│
├── 📂 docs/
│   └── 🖼️ ARCHITECTURE.png               ← Architecture diagram
│
└── 📂 logs-sample/
    └── 📄 sample-report.log              ← Example log output
```

---

## 🔍 Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `aws: command not found` | AWS CLI not in PATH | Add `PATH=/usr/local/bin:$PATH` to crontab |
| `AccessDenied` on any service | Missing IAM permission | Check `iam/policy.json` is correctly attached |
| SES `MessageRejected` | Email not verified | Verify both sender + recipient in SES console |
| S3 `NoSuchBucket` | Wrong bucket name | Check `S3_BUCKET` variable in script |
| Empty log sections | No resources in that service | Normal — section appears empty if service unused |
| Cron not running | Cron service stopped | `sudo systemctl start cron` (Ubuntu) or `crond` |
| CloudFront empty | Wrong region | CloudFront always uses `us-east-1` (handled automatically) |
| Pre-signed URL expired | URL > 7 days old | Re-run script to generate fresh report |

---

<div align="center">

Built with using AWS CLI + Bash + Cron

**[Report Bug](https://github.com/sumzbiz/aws-daily-resource-monitor/issues)** · **[Request Feature](https://github.com/sumzbiz/aws-daily-resource-monitor/issues)**

</div>
