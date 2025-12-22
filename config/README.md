# Bitres Configuration Files Directory

## Directory Structure

```
config/
├── nginx-hardhat-proxy.conf  # Nginx reverse proxy configuration template
├── ssl/                       # SSL certificate directory (auto-generated)
│   ├── hardhat-rpc.crt       # SSL certificate
│   ├── hardhat-rpc.key       # SSL private key
│   └── openssl.cnf           # OpenSSL configuration (auto-generated)
└── README.md                  # This file
```

## File Description

### nginx-hardhat-proxy.conf

**Purpose**: Nginx HTTPS reverse proxy configuration template

**Features**:
- Listens on port 8546 (HTTPS)
- Proxies to Hardhat node (HTTP 8545)
- SSL/TLS encryption
- CORS support
- WebSocket support
- Health check endpoint

**Installation Location**:
- Debian/Ubuntu: `/etc/nginx/sites-available/hardhat-rpc`
- RedHat/CentOS: `/etc/nginx/conf.d/hardhat-rpc.conf`

### ssl/ Directory

**Purpose**: Stores SSL/TLS certificates and private keys

**Files**:
- `hardhat-rpc.crt`: SSL certificate (public key)
- `hardhat-rpc.key`: SSL private key
- `openssl.cnf`: OpenSSL configuration file

**Generation Method**:
```bash
bash scripts/setup-ssl-cert.sh
```

**Certificate Types**:
1. Self-signed certificate (default, development environment)
   - Validity: 10 years
   - Supports: localhost, 127.0.0.1, local machine IP
   - Note: Browser will show warning

2. Let's Encrypt certificate (production environment)
   - Validity: 90 days
   - Requires: Public domain
   - Auto-renewal support

**Security Tips**:
- Private key file permissions should be 600
- Do not commit private key to Git
- Use Let's Encrypt certificate in production

## Usage

### Initialize Configuration

```bash
# Method 1: Auto configuration (recommended)
bash scripts/main/start-brs-system.sh

# Method 2: Manual configuration
bash scripts/setup-ssl-cert.sh        # Generate SSL certificate
bash scripts/setup-nginx-proxy.sh     # Configure Nginx
```

### Update Configuration

If `nginx-hardhat-proxy.conf` is modified:

```bash
# 1. Reinstall configuration
sudo cp config/nginx-hardhat-proxy.conf /etc/nginx/sites-available/hardhat-rpc

# 2. Test configuration
sudo nginx -t

# 3. Reload
sudo systemctl reload nginx
```

### Regenerate Certificate

```bash
# Backup existing certificate
mv config/ssl/hardhat-rpc.crt config/ssl/hardhat-rpc.crt.bak
mv config/ssl/hardhat-rpc.key config/ssl/hardhat-rpc.key.bak

# Generate new certificate
bash scripts/setup-ssl-cert.sh

# Restart Nginx
sudo systemctl restart nginx
```

## Configuration Parameters

### Nginx Configuration Key Parameters

| Parameter | Value | Description |
|------|-----|------|
| Listen Port | 8546 | HTTPS port |
| Upstream Port | 8545 | Hardhat HTTP port |
| SSL Protocol | TLSv1.2, TLSv1.3 | Supported TLS versions |
| Connection Timeout | 600s | Suitable for long queries |
| Request Body Size | 100M | Maximum request size |

### SSL Configuration

| Parameter | Value | Description |
|------|-----|------|
| Certificate Location | config/ssl/hardhat-rpc.crt | SSL certificate |
| Private Key Location | config/ssl/hardhat-rpc.key | Private key |
| Session Cache | 10m | Session cache size |
| Session Timeout | 10m | Session timeout duration |

## Log Files

| Log Type | Path |
|----------|------|
| Access Log | `/tmp/brs-logs/nginx-hardhat-access.log` |
| Error Log | `/tmp/brs-logs/nginx-hardhat-error.log` |

View logs:
```bash
# Access log
tail -f /tmp/brs-logs/nginx-hardhat-access.log

# Error log
tail -f /tmp/brs-logs/nginx-hardhat-error.log

# All logs
tail -f /tmp/brs-logs/*.log
```

## Environment Variables

| Variable | Default | Description |
|------|--------|------|
| ENABLE_HTTPS | true | Enable HTTPS proxy |
| HARDHAT_HOST | 0.0.0.0 | Hardhat listen address |

Usage examples:
```bash
# Disable HTTPS
ENABLE_HTTPS=false bash scripts/main/start-brs-system.sh

# Listen on localhost only
HARDHAT_HOST=127.0.0.1 bash scripts/main/start-brs-system.sh
```

## Troubleshooting

### Certificate Expired

```bash
# View certificate validity
openssl x509 -in config/ssl/hardhat-rpc.crt -noout -dates

# Regenerate certificate
bash scripts/setup-ssl-cert.sh
```

### Nginx Configuration Error

```bash
# Test configuration
sudo nginx -t

# View error log
tail -50 /tmp/brs-logs/nginx-hardhat-error.log

# Restore default configuration
sudo cp config/nginx-hardhat-proxy.conf /etc/nginx/sites-available/hardhat-rpc
sudo nginx -t
sudo systemctl reload nginx
```

### Permission Issues

```bash
# Fix certificate permissions
chmod 600 config/ssl/hardhat-rpc.key
chmod 644 config/ssl/hardhat-rpc.crt

# Fix directory permissions
chmod 755 config/ssl
```

## Security Recommendations

### Development Environment
- Use self-signed certificate
- Allow all CORS
- Listen on 0.0.0.0

### Production Environment
- Use Let's Encrypt certificate
- Restrict CORS domains
- Configure firewall
- Enable access logging
- Set rate limiting
- Listen on public IP only

Production additional configuration:
```nginx
# Restrict CORS
add_header 'Access-Control-Allow-Origin' 'https://yourdomain.com';

# Rate limiting
limit_req_zone $binary_remote_addr zone=rpc:10m rate=10r/s;
```

## Related Documentation

- [HTTPS Proxy Setup Guide](../docs/HTTPS_PROXY_SETUP.md)
- [Quick Start](../HTTPS_QUICK_START.md)
- [Nginx Official Documentation](https://nginx.org/en/docs/)

## Git Configuration

`.gitignore` is configured to ignore:
```
config/ssl/*.key
config/ssl/*.crt
config/ssl/openssl.cnf
```

**Note**: SSL certificates and private keys should not be committed to version control
