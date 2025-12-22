# WSL port forwarding cleanup script
# Run in Windows PowerShell (Administrator)

$ports = @(8545, 8546, 3000)

Write-Host "Cleaning WSL port forwarding rules..." -ForegroundColor Yellow

# Remove port forwarding rules
foreach ($port in $ports) {
    Write-Host "Removing port forwarding for $port" -ForegroundColor Cyan
    netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0
}

# Remove firewall rules
foreach ($port in $ports) {
    $ruleName = "WSL BRS Port $port"
    Write-Host "Removing firewall rule: $ruleName" -ForegroundColor Cyan
    netsh advfirewall firewall delete rule name="$ruleName"
}

Write-Host "`n✅ Cleanup complete!" -ForegroundColor Green
