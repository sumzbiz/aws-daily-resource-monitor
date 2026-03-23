#!/bin/bash

# ============================================================
#  AWS Daily Resource Monitor
#  Version: 1.0.0
#  Author:  SUMAN N
#  GitHub:  https://github.com/sumzbiz/aws-daily-resource-monitor
#
#  Collects AWS resource inventories from 14 services,
#  saves to a log file, uploads to S3, and sends a
#  daily email report via Amazon SES.
# ============================================================

set -euo pipefail   # Exit on error, unset var, or pipe failure

# ─────────────────────────────────────────────────────────────
#  CONFIGURATION — UPDATE THESE VALUES BEFORE RUNNING
# ─────────────────────────────────────────────────────────────

S3_BUCKET="YOUR-BUCKET-NAME"                        # Your S3 bucket name
AWS_REGION="us-east-1"                              # Your AWS region
SENDER_EMAIL="your-verified@email.com"              # SES-verified sender email
RECIPIENT_EMAIL="your-verified@email.com"           # SES-verified recipient email
PRESIGN_EXPIRY_SECONDS=604800                       # 7 days in seconds
LOG_DIR="/home/ec2-user/aws-monitor/logs"           # Local log directory

# ─────────────────────────────────────────────────────────────
#  INTERNAL SETUP — DO NOT EDIT BELOW THIS LINE
# ─────────────────────────────────────────────────────────────

SCRIPT_VERSION="1.0.0"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DATE_READABLE=$(date +"%B %d, %Y at %I:%M %p")
LOG_FILE="$LOG_DIR/aws-resources-$TIMESTAMP.log"
S3_KEY="daily-reports/aws-resources-$TIMESTAMP.log"
ERROR_COUNT=0
SECTION_COUNT=0

# Colors for terminal output (disabled in cron)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
fi

# ─────────────────────────────────────────────────────────────
#  HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────

log_info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; ERROR_COUNT=$((ERROR_COUNT + 1)); }
log_section() { echo -e "${CYAN}[STEP]${NC}  $1"; }

write_header() {
    {
        echo ""
        echo "============================================================"
        echo "  AWS DAILY RESOURCE REPORT — v${SCRIPT_VERSION}"
        echo "  Generated : $DATE_READABLE"
        echo "  Region    : $AWS_REGION"
        echo "  Log File  : $LOG_FILE"
        echo "============================================================"
        echo ""
    } >> "$LOG_FILE"
}

write_section() {
    SECTION_COUNT=$((SECTION_COUNT + 1))
    local label="$1"
    {
        echo ""
        echo "────────────────────────────────────────────────────────────"
        printf "  [%02d] %s\n" "$SECTION_COUNT" "$label"
        echo "────────────────────────────────────────────────────────────"
        echo ""
    } >> "$LOG_FILE"
    log_info "Collecting: $label"
}

write_footer() {
    {
        echo ""
        echo "============================================================"
        echo "  END OF REPORT"
        echo "  Completed   : $(date +"%B %d, %Y at %I:%M %p")"
        echo "  Total Sections: $SECTION_COUNT"
        echo "  Errors Logged : $ERROR_COUNT"
        echo "============================================================"
    } >> "$LOG_FILE"
}

# Run an AWS command safely — don't abort on empty/error output
safe_aws() {
    "$@" 2>> "$LOG_FILE" || echo "  (No data returned or insufficient permissions)" >> "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────
#  PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────

preflight_checks() {
    log_section "Running pre-flight checks..."

    # Check AWS CLI is installed
    if ! command -v aws &>/dev/null; then
        log_error "AWS CLI is not installed or not in PATH. Aborting."
        exit 1
    fi

    # Check AWS credentials are configured
    if ! aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null; then
        log_error "AWS credentials are not configured or invalid. Run: aws configure"
        exit 1
    fi

    # Check required variables are set
    for var in S3_BUCKET AWS_REGION SENDER_EMAIL RECIPIENT_EMAIL; do
        local val="${!var}"
        if [[ "$val" == "YOUR-BUCKET-NAME" ]] || [[ "$val" == "your-verified@email.com" ]]; then
            log_error "Variable $var has not been configured. Please edit the CONFIGURATION block."
            exit 1
        fi
    done

    # Create log directory
    mkdir -p "$LOG_DIR"

    log_info "Pre-flight checks passed ✓"
    log_info "AWS CLI: $(aws --version 2>&1 | cut -d' ' -f1)"
    log_info "Region: $AWS_REGION"
    log_info "Log file: $LOG_FILE"
}

# ─────────────────────────────────────────────────────────────
#  RESOURCE COLLECTION
# ─────────────────────────────────────────────────────────────

collect_ec2() {
    write_section "EC2 — INSTANCES"
    safe_aws aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PublicIpAddress,PrivateIpAddress,Tags[?Key==`Name`].Value|[0],LaunchTime]' \
        --output table >> "$LOG_FILE"

    write_section "EC2 — SECURITY GROUPS"
    safe_aws aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --query 'SecurityGroups[*].[GroupId,GroupName,VpcId,Description]' \
        --output table >> "$LOG_FILE"

    write_section "EC2 — KEY PAIRS"
    safe_aws aws ec2 describe-key-pairs \
        --region "$AWS_REGION" \
        --query 'KeyPairs[*].[KeyName,KeyPairId,CreateTime]' \
        --output table >> "$LOG_FILE"
}

collect_rds() {
    write_section "RDS — DATABASE INSTANCES"
    safe_aws aws rds describe-db-instances \
        --region "$AWS_REGION" \
        --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,EngineVersion,DBInstanceStatus,Endpoint.Address,MultiAZ]' \
        --output table >> "$LOG_FILE"

    write_section "RDS — DB SNAPSHOTS"
    safe_aws aws rds describe-db-snapshots \
        --region "$AWS_REGION" \
        --query 'DBSnapshots[*].[DBSnapshotIdentifier,DBInstanceIdentifier,SnapshotType,Status,SnapshotCreateTime]' \
        --output table >> "$LOG_FILE"
}

collect_s3() {
    write_section "S3 — ALL BUCKETS"
    safe_aws aws s3 ls >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    local bucket_count
    bucket_count=$(aws s3 ls 2>/dev/null | wc -l)
    echo "  Total Buckets: $bucket_count" >> "$LOG_FILE"
}

collect_cloudfront() {
    write_section "CLOUDFRONT — DISTRIBUTIONS"
    # CloudFront is always global (us-east-1)
    safe_aws aws cloudfront list-distributions \
        --region us-east-1 \
        --query 'DistributionList.Items[*].[Id,DomainName,Status,PriceClass,Origins.Items[0].DomainName]' \
        --output table >> "$LOG_FILE"
}

collect_vpc() {
    write_section "VPC — VIRTUAL PRIVATE CLOUDS"
    safe_aws aws ec2 describe-vpcs \
        --region "$AWS_REGION" \
        --query 'Vpcs[*].[VpcId,CidrBlock,State,IsDefault,Tags[?Key==`Name`].Value|[0]]' \
        --output table >> "$LOG_FILE"

    write_section "VPC — SUBNETS"
    safe_aws aws ec2 describe-subnets \
        --region "$AWS_REGION" \
        --query 'Subnets[*].[SubnetId,VpcId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch,AvailableIpAddressCount]' \
        --output table >> "$LOG_FILE"

    write_section "VPC — INTERNET GATEWAYS"
    safe_aws aws ec2 describe-internet-gateways \
        --region "$AWS_REGION" \
        --query 'InternetGateways[*].[InternetGatewayId,Attachments[0].VpcId,Attachments[0].State]' \
        --output table >> "$LOG_FILE"

    write_section "VPC — NAT GATEWAYS"
    safe_aws aws ec2 describe-nat-gateways \
        --region "$AWS_REGION" \
        --query 'NatGateways[*].[NatGatewayId,VpcId,SubnetId,State,ConnectivityType]' \
        --output table >> "$LOG_FILE"

    write_section "VPC — ELASTIC IPs"
    safe_aws aws ec2 describe-addresses \
        --region "$AWS_REGION" \
        --query 'Addresses[*].[PublicIp,AllocationId,AssociationId,InstanceId,Domain]' \
        --output table >> "$LOG_FILE"
}

collect_iam() {
    write_section "IAM — USERS"
    safe_aws aws iam list-users \
        --query 'Users[*].[UserName,UserId,CreateDate,PasswordLastUsed]' \
        --output table >> "$LOG_FILE"

    write_section "IAM — ROLES"
    safe_aws aws iam list-roles \
        --query 'Roles[*].[RoleName,RoleId,CreateDate,Description]' \
        --output table >> "$LOG_FILE"

    write_section "IAM — GROUPS"
    safe_aws aws iam list-groups \
        --query 'Groups[*].[GroupName,GroupId,CreateDate]' \
        --output table >> "$LOG_FILE"

    write_section "IAM — CUSTOMER MANAGED POLICIES"
    safe_aws aws iam list-policies \
        --scope Local \
        --query 'Policies[*].[PolicyName,PolicyId,AttachmentCount,CreateDate]' \
        --output table >> "$LOG_FILE"
}

collect_route53() {
    write_section "ROUTE 53 — HOSTED ZONES"
    safe_aws aws route53 list-hosted-zones \
        --query 'HostedZones[*].[Name,Id,Config.PrivateZone,ResourceRecordSetCount,Config.Comment]' \
        --output table >> "$LOG_FILE"
}

collect_cloudwatch() {
    write_section "CLOUDWATCH — ALARMS"
    safe_aws aws cloudwatch describe-alarms \
        --region "$AWS_REGION" \
        --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName,Namespace,ComparisonOperator]' \
        --output table >> "$LOG_FILE"

    write_section "CLOUDWATCH — LOG GROUPS"
    safe_aws aws logs describe-log-groups \
        --region "$AWS_REGION" \
        --query 'logGroups[*].[logGroupName,retentionInDays,storedBytes,creationTime]' \
        --output table >> "$LOG_FILE"
}

collect_cloudformation() {
    write_section "CLOUDFORMATION — STACKS"
    safe_aws aws cloudformation list-stacks \
        --region "$AWS_REGION" \
        --query 'StackSummaries[?StackStatus!=`DELETE_COMPLETE`].[StackName,StackStatus,CreationTime,LastUpdatedTime]' \
        --output table >> "$LOG_FILE"
}

collect_lambda() {
    write_section "LAMBDA — FUNCTIONS"
    safe_aws aws lambda list-functions \
        --region "$AWS_REGION" \
        --query 'Functions[*].[FunctionName,Runtime,MemorySize,Timeout,LastModified,CodeSize]' \
        --output table >> "$LOG_FILE"
}

collect_sns() {
    write_section "SNS — TOPICS"
    safe_aws aws sns list-topics \
        --region "$AWS_REGION" \
        --query 'Topics[*].TopicArn' \
        --output table >> "$LOG_FILE"

    write_section "SNS — SUBSCRIPTIONS"
    safe_aws aws sns list-subscriptions \
        --region "$AWS_REGION" \
        --query 'Subscriptions[*].[TopicArn,Protocol,Endpoint,SubscriptionArn]' \
        --output table >> "$LOG_FILE"
}

collect_sqs() {
    write_section "SQS — QUEUES"
    local queues
    queues=$(aws sqs list-queues --region "$AWS_REGION" --query 'QueueUrls' --output text 2>/dev/null)
    if [[ -n "$queues" ]]; then
        echo "$queues" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
        # Get attributes for each queue
        while IFS= read -r queue_url; do
            echo "  Queue: $queue_url" >> "$LOG_FILE"
            safe_aws aws sqs get-queue-attributes \
                --region "$AWS_REGION" \
                --queue-url "$queue_url" \
                --attribute-names ApproximateNumberOfMessages MessageRetentionPeriod \
                --query 'Attributes' \
                --output table >> "$LOG_FILE"
        done <<< "$queues"
    else
        echo "  (No SQS queues found)" >> "$LOG_FILE"
    fi
}

collect_dynamodb() {
    write_section "DYNAMODB — TABLES"
    local tables
    tables=$(aws dynamodb list-tables \
        --region "$AWS_REGION" \
        --query 'TableNames' \
        --output text 2>/dev/null)

    if [[ -n "$tables" ]]; then
        safe_aws aws dynamodb list-tables \
            --region "$AWS_REGION" \
            --query 'TableNames' \
            --output table >> "$LOG_FILE"

        echo "" >> "$LOG_FILE"
        echo "  Table Details:" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"

        for table in $tables; do
            echo "  ── Table: $table" >> "$LOG_FILE"
            safe_aws aws dynamodb describe-table \
                --region "$AWS_REGION" \
                --table-name "$table" \
                --query 'Table.[TableStatus,ItemCount,TableSizeBytes,ProvisionedThroughput.ReadCapacityUnits,ProvisionedThroughput.WriteCapacityUnits,BillingModeSummary.BillingMode]' \
                --output table >> "$LOG_FILE"
        done
    else
        echo "  (No DynamoDB tables found)" >> "$LOG_FILE"
    fi
}

collect_ebs() {
    write_section "EBS — VOLUMES"
    safe_aws aws ec2 describe-volumes \
        --region "$AWS_REGION" \
        --query 'Volumes[*].[VolumeId,Size,VolumeType,State,AvailabilityZone,Encrypted,Attachments[0].InstanceId]' \
        --output table >> "$LOG_FILE"

    write_section "EBS — SNAPSHOTS (owned by you)"
    safe_aws aws ec2 describe-snapshots \
        --owner-ids self \
        --region "$AWS_REGION" \
        --query 'Snapshots[*].[SnapshotId,VolumeId,State,StartTime,VolumeSize,Encrypted,Description]' \
        --output table >> "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────
#  S3 UPLOAD + PRESIGNED URL
# ─────────────────────────────────────────────────────────────

upload_to_s3() {
    log_section "Uploading log to S3..."

    if aws s3 cp "$LOG_FILE" "s3://$S3_BUCKET/$S3_KEY" \
        --region "$AWS_REGION" \
        --storage-class STANDARD_IA &>/dev/null; then
        log_info "Upload successful → s3://$S3_BUCKET/$S3_KEY"
    else
        log_error "S3 upload failed! Check bucket name and IAM permissions."
        exit 1
    fi

    log_section "Generating pre-signed URL..."
    PRESIGNED_URL=$(aws s3 presign "s3://$S3_BUCKET/$S3_KEY" \
        --expires-in "$PRESIGN_EXPIRY_SECONDS" \
        --region "$AWS_REGION" 2>/dev/null)

    if [[ -z "$PRESIGNED_URL" ]]; then
        log_error "Pre-signed URL generation failed!"
        exit 1
    fi

    log_info "Pre-signed URL generated (valid for 7 days)"
}

# ─────────────────────────────────────────────────────────────
#  EMAIL DELIVERY VIA SES
# ─────────────────────────────────────────────────────────────

send_email() {
    log_section "Sending email report via Amazon SES..."

    local log_size log_lines
    log_size=$(du -sh "$LOG_FILE" 2>/dev/null | cut -f1)
    log_lines=$(wc -l < "$LOG_FILE")

    local email_body
    email_body="Hello,

Your AWS Daily Resource Report is ready for $DATE_READABLE.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  REPORT SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Date Generated : $DATE_READABLE
  AWS Region     : $AWS_REGION
  File Size      : $log_size
  Total Lines    : $log_lines
  Script Version : $SCRIPT_VERSION

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  DOWNLOAD YOUR REPORT (valid 7 days)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$PRESIGNED_URL

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SERVICES COVERED IN THIS REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✔  EC2 Instances, Security Groups, Key Pairs
  ✔  RDS DB Instances & Snapshots
  ✔  S3 Buckets
  ✔  CloudFront Distributions
  ✔  VPC, Subnets, IGW, NAT Gateway, Elastic IPs
  ✔  IAM Users, Roles, Groups, Policies
  ✔  Route 53 Hosted Zones
  ✔  CloudWatch Alarms & Log Groups
  ✔  CloudFormation Stacks
  ✔  Lambda Functions
  ✔  SNS Topics & Subscriptions
  ✔  SQS Queues
  ✔  DynamoDB Tables (with details)
  ✔  EBS Volumes & Snapshots

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
This is an automated report generated by aws-daily-resource-monitor.
GitHub: https://github.com/sumzbiz/aws-daily-resource-monitor
"

    if aws ses send-email \
        --from "$SENDER_EMAIL" \
        --to "$RECIPIENT_EMAIL" \
        --subject "AWS Daily Resource Report — $DATE_READABLE" \
        --text "$email_body" \
        --region "$AWS_REGION" &>/dev/null; then
        log_info "Email delivered successfully → $RECIPIENT_EMAIL"
    else
        log_error "Email delivery failed. Check SES verification and sandbox mode."
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────
#  CLEANUP OLD LOGS
# ─────────────────────────────────────────────────────────────

cleanup_old_logs() {
    local deleted_count
    deleted_count=$(find "$LOG_DIR" -name "aws-resources-*.log" -mtime +30 2>/dev/null | wc -l)
    find "$LOG_DIR" -name "aws-resources-*.log" -mtime +30 -delete 2>/dev/null
    if [[ "$deleted_count" -gt 0 ]]; then
        log_info "Cleaned up $deleted_count old log file(s) (older than 30 days)"
    fi
}

# ─────────────────────────────────────────────────────────────
#  MAIN EXECUTION
# ─────────────────────────────────────────────────────────────

main() {
    echo ""
    echo "══════════════════════════════════════════════════════"
    echo "  AWS Daily Resource Monitor — v${SCRIPT_VERSION}"
    echo "  Started: $DATE_READABLE"
    echo "══════════════════════════════════════════════════════"
    echo ""

    # Pre-flight checks
    preflight_checks

    # Start log file
    write_header

    # Collect resources from all 14 services
    log_section "Starting resource collection across all AWS services..."
    collect_ec2
    collect_rds
    collect_s3
    collect_cloudfront
    collect_vpc
    collect_iam
    collect_route53
    collect_cloudwatch
    collect_cloudformation
    collect_lambda
    collect_sns
    collect_sqs
    collect_dynamodb
    collect_ebs

    # Write footer
    write_footer

    log_info "Resource collection complete — $SECTION_COUNT sections written"

    # Upload to S3 and generate presigned URL
    upload_to_s3

    # Send email
    send_email

    # Clean up old logs
    cleanup_old_logs

    echo ""
    echo "══════════════════════════════════════════════════════"
    echo "  ✓  Script completed successfully"
    echo "  Log   : $LOG_FILE"
    echo "  S3    : s3://$S3_BUCKET/$S3_KEY"
    echo "  Email : $RECIPIENT_EMAIL"
    if [[ "$ERROR_COUNT" -gt 0 ]]; then
        echo "  Warns : $ERROR_COUNT non-fatal error(s) logged"
    fi
    echo "══════════════════════════════════════════════════════"
    echo ""
}

# Run main function
main "$@"
