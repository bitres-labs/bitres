# Bitres System - WSL Port Forwarding to Windows Configuration

## Description

These scripts are used to forward Bitres system ports running in WSL to the Windows host, enabling:
- Access to WSL services through Windows IP address
- Mobile phones and other devices can access via LAN

## File List

```
scripts/windows/
├── setup-port-forwarding.bat       # One-click setup (double-click to run)
├── setup-port-forwarding.ps1       # PowerShell setup script
├── cleanup-port-forwarding.bat     # One-click cleanup (double-click to run)
├── cleanup-port-forwarding.ps1     # PowerShell cleanup script
└── README.md                       # This file
```

## Quick Start

### Method 1: Double-Click to Run (Recommended)

1. **In Windows File Explorer**, navigate to:
   ```
   \\wsl$\Ubuntu\home\biostar\work\brs\scripts\windows
   ```

2. **Double-click**: `setup-port-forwarding.bat`

3. Click "Yes" in the UAC prompt (requires administrator privileges)

4. Wait for configuration to complete

### Method 2: PowerShell Manual Run

1. Open PowerShell **as Administrator**

2. Run script:
   ```powershell
   cd "\\wsl$\Ubuntu\home\biostar\work\brs\scripts\windows"
   .\setup-port-forwarding.ps1
   ```

3. Follow the prompts

## Forwarded Ports

| Port | Service | Description |
|------|------|------|
| 8545 | Hardhat Node | Blockchain backend RPC service |
| 3000 | Frontend Dev Server | Web frontend interface |

## Configuration Details

The script will automatically complete the following configurations:

### 1. Port Forwarding Rules
```
0.0.0.0:8545 -> WSL_IP:8545
0.0.0.0:3000 -> WSL_IP:3000
```

### 2. Windows Firewall Rules
- Allow TCP 8545 inbound connections
- Allow TCP 3000 inbound connections

## Access URLs

After configuration is complete, you can access via the following addresses:

### Windows Local Access
```
Frontend: http://localhost:3000
Backend: http://localhost:8545
```

### LAN Access (Mobile Devices, etc.)
```
Frontend: http://192.168.2.151:3000
Backend: http://192.168.2.151:8545
```
> Note: 192.168.2.151 is an example IP; check script output for actual IP

### WSL Internal Access
```
Frontend: http://WSL_IP:3000
Backend: http://WSL_IP:8545
```

## Test Configuration

### 1. Test Local Access

Open in Windows browser:
```
http://localhost:3000
```

### 2. Test LAN Access

Open in mobile browser:
```
http://Your_Windows_IP:3000
```

### 3. Test Backend Connection

Run in PowerShell:
```powershell
curl http://localhost:8545 -Method POST -Headers @{"Content-Type"="application/json"} -Body '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

Should return the current block number.

## View Current Configuration

### View Port Forwarding Rules
```powershell
netsh interface portproxy show v4tov4
```

### View Firewall Rules
```powershell
Get-NetFirewallRule -Name "BRS-*" | Format-Table Name, DisplayName, Enabled
```

### View WSL IP
```bash
# Run in WSL
ip addr show eth0 | grep inet
```

## Cleanup Configuration

### Method 1: Double-Click to Run
Double-click `cleanup-port-forwarding.bat`

### Method 2: PowerShell Run
```powershell
# Run as Administrator
.\cleanup-port-forwarding.ps1
```

This will delete:
- All Bitres port forwarding rules
- All Bitres firewall rules

## Important Notes

### 1. WSL IP Address Changes
After each WSL restart, the IP address may change. If connection issues occur:
- Re-run the setup script
- Or manually update port forwarding rules

### 2. Administrator Privileges
All operations require administrator privileges because:
- Port forwarding requires network configuration modification
- Firewall rules require administrator access

### 3. Firewall Software
If using third-party firewall software (e.g., 360, Norton, etc.), you may need to manually add rules to allow:
- TCP 8545
- TCP 3000

### 4. Security
Port forwarding exposes WSL services to the LAN:
- Use only on trusted networks
- Do not use on public Wi-Fi
- Run cleanup script after testing

## Handling WSL Restart

### Automatic Method (Recommended)
Create a Windows scheduled task to automatically run the setup script when WSL starts.

### Manual Method
After each WSL restart, re-run:
```
setup-port-forwarding.bat
```

## FAQ

### Q1: Double-clicking script has no response?
**A**: Check:
- Whether Windows has disabled .bat file execution
- Whether PowerShell execution policy is restricted
- Try manually running the PowerShell script as administrator

### Q2: Mobile cannot access?
**A**: Check:
1. Whether mobile and computer are on the same Wi-Fi network
2. Whether Windows firewall is correctly configured (run setup script)
3. Whether router has AP isolation enabled
4. Try temporarily disabling Windows Defender firewall for testing

### Q3: Port forwarding failed?
**A**:
1. Ensure running as administrator
2. Check if port is occupied by another program
3. Check PowerShell error messages

### Q4: WSL service inaccessible after configuration?
**A**:
1. Confirm service is running in WSL
   ```bash
   lsof -i :8545
   lsof -i :3000
   ```
2. Confirm service is listening on `0.0.0.0`, not `127.0.0.1`
3. Check if WSL IP address has changed

### Q5: How to fix WSL IP?
**A**: Create `.wslconfig` file on Windows:
```
# C:\Users\YourUsername\.wslconfig
[wsl2]
networkingMode=mirrored
```
Restart WSL for changes to take effect.

## Advanced Configuration

### Add Custom Ports
Edit `setup-port-forwarding.ps1`, add port to `$PORTS` array:
```powershell
$PORTS = @(8545, 3000, YourPort)
```

### Modify Listen Address
Default listens on `0.0.0.0` (all network interfaces). To listen on specific network only, modify in script:
```powershell
listenaddress=0.0.0.0
```
Change to:
```powershell
listenaddress=192.168.2.151  # Your Windows IP
```

## Technical Support

If you encounter issues:
1. Check script output error messages
2. Check Windows Event Viewer
3. Confirm WSL network is working properly
4. Try cleanup then reconfigure

## License

MIT License - Bitres Team 2025

---

**Last Updated**: 2025-11-09
