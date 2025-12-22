#!/bin/bash

# SSL certificate generator
# Supports self-signed certificates and Let's Encrypt certificates

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SSL_DIR="/home/biostar/work/brs/config/ssl"
CERT_NAME="hardhat-rpc"
CERT_FILE="$SSL_DIR/$CERT_NAME.crt"
KEY_FILE="$SSL_DIR/$CERT_NAME.key"
DAYS_VALID=3650  # 10 years

print_step() {
    echo -e "${GREEN}▶ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Ensure SSL directory exists
mkdir -p "$SSL_DIR"

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}SSL certificate generator${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# Check for existing certificate
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo -e "${YELLOW}Existing certificate detected:${NC}"
    echo "  Cert: $CERT_FILE"
    echo "  Key : $KEY_FILE"
    echo ""

    if command -v openssl &> /dev/null; then
        echo -e "${BLUE}Certificate info:${NC}"
        openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates 2>/dev/null || true
        echo ""
    fi

    read -p "Regenerate certificate? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_success "Using existing certificate"
        exit 0
    fi

    print_step "Backing up existing certificate..."
    BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)
    mv "$CERT_FILE" "$CERT_FILE.$BACKUP_SUFFIX"
    mv "$KEY_FILE" "$KEY_FILE.$BACKUP_SUFFIX"
    print_success "Backed up to *.$BACKUP_SUFFIX"
    echo ""
fi

# Choose certificate type
echo -e "${BLUE}Choose certificate type:${NC}"
echo "  1) Self-signed (recommended for development)"
echo "  2) Let's Encrypt (requires public domain)"
echo ""
read -p "Select [1-2] (default 1): " CERT_TYPE
CERT_TYPE=${CERT_TYPE:-1}

if [ "$CERT_TYPE" == "2" ]; then
    print_step "Issuing Let's Encrypt certificate..."

    if ! command -v certbot &> /dev/null; then
        print_error "certbot not installed, installing..."
        sudo apt update && sudo apt install -y certbot
    fi

    read -p "Enter domain (e.g., rpc.example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        print_error "Domain cannot be empty"
        exit 1
    fi

    print_warning "Ensure $DOMAIN resolves to this host and port 80 is free"
    read -p "Press Enter to continue..."

    sudo certbot certonly --standalone \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email admin@$DOMAIN \
        || {
            print_error "Let's Encrypt failed; falling back to self-signed"
            CERT_TYPE=1
        }

    if [ "$CERT_TYPE" == "2" ]; then
        sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem "$CERT_FILE"
        sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem "$KEY_FILE"
        sudo chown "$(whoami)":"$(whoami)" "$CERT_FILE" "$KEY_FILE"

        print_success "Let's Encrypt certificate generated"
        echo "  Cert: $CERT_FILE"
        echo "  Key : $KEY_FILE"
        echo ""
        print_warning "Cert expires in ~90 days; set up auto-renewal:"
        echo "  sudo certbot renew --dry-run"
        exit 0
    fi
fi

# Self-signed certificate path
print_step "Generating self-signed certificate..."

if ! command -v openssl &> /dev/null; then
    print_error "openssl not installed"
    exit 1
fi

HOST_IP=$(hostname -I | awk '{print $1}')

cat > "$SSL_DIR/openssl.cnf" <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = v3_req
prompt             = no

[ req_distinguished_name ]
C  = US
ST = State
L  = City
O  = BRS
CN = $HOST_IP

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
IP.1 = $HOST_IP
IP.2 = 127.0.0.1
EOF

openssl req -x509 -nodes -days $DAYS_VALID -newkey rsa:2048 \
  -keyout "$KEY_FILE" -out "$CERT_FILE" -config "$SSL_DIR/openssl.cnf" >/dev/null 2>&1

chmod 600 "$KEY_FILE"

print_success "Self-signed certificate generated"
echo "  Cert: $CERT_FILE"
echo "  Key : $KEY_FILE"
echo "  Valid: $DAYS_VALID days"
echo ""

if command -v openssl &> /dev/null; then
    echo -e "${BLUE}Certificate info:${NC}"
    openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates 2>/dev/null || true
    echo ""
fi

print_warning "Self-signed certificates show browser warnings"
echo "  Options:"
echo "  1. Manually trust the certificate in your browser"
echo "  2. Ignore SSL verification in code (development only)"
echo "  3. Use Let's Encrypt for production"

print_success "SSL certificate setup complete"
