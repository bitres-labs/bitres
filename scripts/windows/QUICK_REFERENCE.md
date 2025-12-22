# WSL Port Forwarding - Quick Reference Card

## Quick Setup

```
Open in Windows File Explorer:
\\wsl$\Ubuntu\home\biostar\work\brs\scripts\windows

Double-click: setup-port-forwarding.bat
```

## Access URLs

| Device | Frontend | Backend |
|------|------|------|
| **Windows Local** | http://localhost:3000 | http://localhost:8545 |
| **Mobile/Other Devices** | http://192.168.2.151:3000 | http://192.168.2.151:8545 |

> Note: Actual IP may vary; check script output

## Check Commands

### View Port Forwarding
```powershell
netsh interface portproxy show v4tov4
```

### View Firewall Rules
```powershell
Get-NetFirewallRule -Name "BRS-*"
```

### View WSL IP
```bash
# Run in WSL
ip addr show eth0 | grep inet
```

## Cleanup Configuration

```
Double-click: cleanup-port-forwarding.bat
```

## Common Issues

### Mobile cannot access?
1. Confirm mobile and computer are on same Wi-Fi
2. Re-run setup-port-forwarding.bat
3. Temporarily disable firewall for testing

### Configuration invalid after WSL restart?
```
Re-run: setup-port-forwarding.bat
```

### Port occupied?
```powershell
# Check port usage
netstat -ano | findstr :3000
netstat -ano | findstr :8545
```

## File Locations

```
scripts/windows/
├── setup-port-forwarding.bat    <- Setup (double-click)
├── cleanup-port-forwarding.bat  <- Cleanup (double-click)
└── README.md                    <- Full documentation
```

---
**Tip**: Requires administrator privileges to run
