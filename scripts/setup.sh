#!/bin/bash

# ============================================================
#  AWS Daily Resource Monitor — Setup Script
#  Prepares the environment for first-time use
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${CYAN}──── $1 ────${NC}"; }

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   AWS Daily Resource Monitor — Setup Script     ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ─────────────────────────────────────────────────────────────
#  STEP 1: Check Operating System
# ─────────────────────────────────────────────────────────────
section "Checking Operating System"

OS_TYPE=""
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_TYPE="$ID"
    info "Detected OS: $PRETTY_NAME"
else
    warn "Could not detect OS type. Proceeding anyway."
fi

# ─────────────────────────────────────────────────────────────
#  STEP 2: Install AWS CLI if not present
# ─────────────────────────────────────────────────────────────
section "Checking AWS CLI"

if command -v aws &>/dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d' ' -f1)
    info "AWS CLI already installed: $AWS_VERSION"
else
    warn "AWS CLI not found. Installing..."
    
    # Install curl if missing
    if ! command -v curl &>/dev/null; then
        if [[ "$OS_TYPE" == "ubuntu" ]] || [[ "$OS_TYPE" == "debian" ]]; then
            sudo apt-get update -qq && sudo apt-get install -y curl unzip
        elif [[ "$OS_TYPE" == "amzn" ]] || [[ "$OS_TYPE" == "centos" ]]; then
            sudo yum install -y curl unzip
        fi
    fi

    # Download and install AWS CLI v2
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp/
    sudo /tmp/aws/install
    rm -rf /tmp/aws /tmp/awscliv2.zip

    if command -v aws &>/dev/null; then
        info "AWS CLI installed successfully: $(aws --version 2>&1 | cut -d' ' -f1)"
    else
        error "AWS CLI installation failed. Please install manually."
    fi
fi

# ─────────────────────────────────────────────────────────────
#  STEP 3: Check AWS credentials
# ─────────────────────────────────────────────────────────────
section "Checking AWS Credentials"

if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
    info "AWS credentials valid"
    info "Account ID : $ACCOUNT_ID"
    info "Identity   : $USER_ARN"
else
    warn "AWS credentials not configured or invalid."
    echo ""
    echo "  Please run: aws configure"
    echo "  You will need:"
    echo "    - AWS Access Key ID"
    echo "    - AWS Secret Access Key"
    echo "    - Default region (e.g., us-east-1)"
    echo "    - Output format: json"
    echo ""
    read -rp "  Do you want to run 'aws configure' now? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        aws configure
    else
        warn "Skipping credential setup. Run 'aws configure' before using the monitor."
    fi
fi

# ─────────────────────────────────────────────────────────────
#  STEP 4: Create directory structure
# ─────────────────────────────────────────────────────────────
section "Creating Directory Structure"

HOME_DIR="$HOME/aws-monitor"
LOG_DIR="$HOME_DIR/logs"

mkdir -p "$LOG_DIR"
info "Created: $HOME_DIR"
info "Created: $LOG_DIR"

# ─────────────────────────────────────────────────────────────
#  STEP 5: Copy script to working directory
# ─────────────────────────────────────────────────────────────
section "Setting Up Script"

SCRIPT_SRC="$(dirname "$0")/aws_resource_monitor.sh"
SCRIPT_DST="$HOME_DIR/aws_resource_monitor.sh"

if [[ -f "$SCRIPT_SRC" ]]; then
    cp "$SCRIPT_SRC" "$SCRIPT_DST"
    chmod +x "$SCRIPT_DST"
    info "Script copied to: $SCRIPT_DST"
    info "Script made executable"
else
    warn "Could not find aws_resource_monitor.sh in ./scripts/"
    warn "Please manually copy it to: $HOME_DIR/"
fi

# ─────────────────────────────────────────────────────────────
#  STEP 6: Install jq (optional, useful for JSON parsing)
# ─────────────────────────────────────────────────────────────
section "Checking Optional Tools"

if command -v jq &>/dev/null; then
    info "jq is installed: $(jq --version)"
else
    warn "jq is not installed (optional but useful for JSON parsing)"
    read -rp "  Install jq? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        if [[ "$OS_TYPE" == "ubuntu" ]] || [[ "$OS_TYPE" == "debian" ]]; then
            sudo apt-get install -y jq
        elif [[ "$OS_TYPE" == "amzn" ]] || [[ "$OS_TYPE" == "centos" ]]; then
            sudo yum install -y jq
        fi
        info "jq installed"
    fi
fi

# ─────────────────────────────────────────────────────────────
#  STEP 7: Summary and next steps
# ─────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║               SETUP COMPLETE — NEXT STEPS               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  1. Edit the configuration block in the script:"
echo "     nano $SCRIPT_DST"
echo ""
echo "  2. Update these 4 required values:"
echo "     → S3_BUCKET       Your S3 bucket name"
echo "     → AWS_REGION      Your AWS region (e.g., us-east-1)"
echo "     → SENDER_EMAIL    Your SES-verified sender email"
echo "     → RECIPIENT_EMAIL Your SES-verified recipient email"
echo ""
echo "  3. Test the script manually:"
echo "     bash $SCRIPT_DST"
echo ""
echo "  4. Add the cron job (runs daily at 5 PM):"
echo "     crontab -e"
echo ""
echo "     Add these two lines:"
echo "     PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
echo "     0 17 * * * /bin/bash $SCRIPT_DST >> $LOG_DIR/cron_output.log 2>&1"
echo ""
echo "  5. See README.md for full setup guide."
echo ""
