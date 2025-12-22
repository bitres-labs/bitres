# WSL port forwarding setup script
# Run in Windows PowerShell (Administrator)

# Get WSL IP address
$wslIP = (wsl hostname -I).Trim()
Write-Host "WSL IP: $wslIP" -ForegroundColor Green

# Ports to forward
$ports = @(8545, 8546, 3000)

# Remove old portproxy rules
Write-Host "`nCleaning old port forwarding rules..." -ForegroundColor Yellow
foreach ($port in $ports) {
    netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 2>$null
}

# Add new portproxy rules
Write-Host "`nAdding port forwarding rules..." -ForegroundColor Yellow
foreach ($port in $ports) {
    Write-Host "Forward port $port -> $wslIP`:$port" -ForegroundColor Cyan
    netsh interface portproxy add v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=$wslIP
}

# Configure firewall rules
Write-Host "`nConfiguring firewall rules..." -ForegroundColor Yellow
foreach ($port in $ports) {
    $ruleName = "WSL BRS Port $port"

    # Remove old rule
    netsh advfirewall firewall delete rule name="$ruleName" 2>$null

    # Add new rule
    Write-Host "Allow port $port through firewall" -ForegroundColor Cyan
    netsh advfirewall firewall add rule name="$ruleName" dir=in action=allow protocol=TCP localport=$port
}

# Show current config
Write-Host "`nCurrent port forwarding config:" -ForegroundColor Green
netsh interface portproxy show all

Write-Host "`n========================================" -ForegroundColor Blue
Write-Host "✅ Setup complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Blue
Write-Host "`nAccess endpoints:" -ForegroundColor Yellow
Write-Host "  Frontend:    http://192.168.2.151:3000" -ForegroundColor Cyan
Write-Host "  HTTPS RPC:   https://192.168.2.151:8546/health" -ForegroundColor Cyan
Write-Host "  HTTP RPC:    http://192.168.2.151:8545" -ForegroundColor Cyan
Write-Host "`nNote: If unreachable, check Windows Firewall settings." -ForegroundColor Yellow
