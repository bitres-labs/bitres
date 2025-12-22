# BRS system - WSL port forwarding to Windows
# Forwards WSL service ports to Windows host for LAN access
# Usage: Run this PowerShell script as Administrator

# Color output helper
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Print header
function Print-Header {
    param([string]$Title)
    Write-ColorOutput "`n================================================================" "Cyan"
    Write-ColorOutput $Title "Cyan"
    Write-ColorOutput "================================================================`n" "Cyan"
}

# Check admin privileges
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Main flow
Clear-Host
Print-Header "🚀 BRS - WSL port forwarding setup"

# Ensure admin
if (-not (Test-Administrator)) {
    Write-ColorOutput "❌ Error: Administrator privileges required" "Red"
    Write-ColorOutput "Right-click PowerShell and choose 'Run as administrator'" "Yellow"
    Write-ColorOutput "`nPress any key to exit..." "Yellow"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-ColorOutput "✅ Administrator check passed`n" "Green"

# Parameters
$PORTS = @(8545, 3000)  # ports to forward
$WSL_IP = bash.exe -c "ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'"
$WINDOWS_IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Wi-Fi*" -or $_.InterfaceAlias -like "*Ethernet*" }).IPAddress | Select-Object -First 1

# Show network info
Print-Header "📡 Network info"
Write-ColorOutput "WSL IP:     $WSL_IP" "Cyan"
Write-ColorOutput "Windows IP: $WINDOWS_IP" "Cyan"
Write-ColorOutput "Ports:      8545 (Hardhat), 3000 (Frontend)`n" "Cyan"

# Confirm proceed
Write-ColorOutput "Continue configuring port forwarding? (Y/N): " "Yellow" -NoNewline
$confirm = Read-Host
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-ColorOutput "`nCancelled" "Yellow"
    exit 0
}

# ============================================================
# Step 1: Remove old port forwarding rules
# ============================================================
Print-Header "Step 1/3: Clean old port forwarding rules"

foreach ($port in $PORTS) {
    Write-ColorOutput "Checking existing rule for port $port..." "White"

    try {
        $existingRule = netsh interface portproxy show v4tov4 | Select-String "0.0.0.0.*$port"
        if ($existingRule) {
            Write-ColorOutput "  Found old rule, deleting..." "Yellow"
            netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 | Out-Null
            Write-ColorOutput "  ✅ Removed old rule for port $port" "Green"
        } else {
            Write-ColorOutput "  ℹ️  No existing rule for port $port" "Gray"
        }
    } catch {
        Write-ColorOutput "  ⚠️  Warning while checking port $port: $($_.Exception.Message)" "Yellow"
    }
}

Write-ColorOutput "`n✅ Old rules cleaned up`n" "Green"

# ============================================================
# Step 2: Add new port forwarding rules
# ============================================================
Print-Header "Step 2/3: Add port forwarding rules"

foreach ($port in $PORTS) {
    Write-ColorOutput "Configuring port $port forwarding..." "White"

    try {
        netsh interface portproxy add v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=$WSL_IP | Out-Null

        # Verify rule added
        $verifyRule = netsh interface portproxy show v4tov4 | Select-String "0.0.0.0.*$port"
        if ($verifyRule) {
            Write-ColorOutput "  ✅ Port $port forwarding added" "Green"
            Write-ColorOutput "     0.0.0.0:$port -> $WSL_IP:$port" "Cyan"
        } else {
            Write-ColorOutput "  ❌ Failed to add port $port forwarding" "Red"
        }
    } catch {
        Write-ColorOutput "  ❌ Port $port setup failed: $($_.Exception.Message)" "Red"
    }
}

Write-ColorOutput "`n✅ Port forwarding configured`n" "Green"

# ============================================================
# Step 3: Configure Windows Firewall rules
# ============================================================
Print-Header "Step 3/3: Configure Windows Firewall"

$FIREWALL_RULES = @(
    @{
        Name = "BRS-Hardhat-TCP-8545"
        DisplayName = "BRS Hardhat Node (TCP 8545)"
        Port = 8545
        Protocol = "TCP"
    },
    @{
        Name = "BRS-Frontend-TCP-3000"
        DisplayName = "BRS Frontend Server (TCP 3000)"
        Port = 3000
        Protocol = "TCP"
    }
)

foreach ($rule in $FIREWALL_RULES) {
    Write-ColorOutput "Configuring firewall rule: $($rule.DisplayName)..." "White"

    try {
        # Delete old rule if exists
        $existingRule = Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
        if ($existingRule) {
            Write-ColorOutput "  Removing old rule..." "Yellow"
            Remove-NetFirewallRule -Name $rule.Name
        }

        # Add new inbound rule
        New-NetFirewallRule `
            -Name $rule.Name `
            -DisplayName $rule.DisplayName `
            -Direction Inbound `
            -Protocol $rule.Protocol `
            -LocalPort $rule.Port `
            -Action Allow `
            -Profile Any `
            -Enabled True | Out-Null

        Write-ColorOutput "  ✅ Firewall rule added: $($rule.DisplayName)" "Green"

    } catch {
        Write-ColorOutput "  ❌ Failed to configure firewall rule: $($_.Exception.Message)" "Red"
    }
}

Write-ColorOutput "`n✅ Firewall configuration complete`n" "Green"

# ============================================================
# Show current configuration
# ============================================================
Print-Header "📋 Current port forwarding config"

Write-ColorOutput "All port forwarding rules:" "Cyan"
netsh interface portproxy show v4tov4

Write-ColorOutput "`nFirewall rule status:" "Cyan"
foreach ($rule in $FIREWALL_RULES) {
    $ruleStatus = Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
    if ($ruleStatus) {
        $status = if ($ruleStatus.Enabled) { "✅ Enabled" } else { "❌ Disabled" }
        Write-ColorOutput "  $($rule.DisplayName): $status" "White"
    }
}

# ============================================================
# Access info
# ============================================================
Print-Header "🌐 Access URLs"

Write-ColorOutput "Local (Windows):" "Cyan"
Write-ColorOutput "  Frontend: http://localhost:3000" "White"
Write-ColorOutput "  Backend:  http://localhost:8545" "White"

Write-ColorOutput "`nLAN (mobile/other devices):" "Cyan"
Write-ColorOutput "  Frontend: http://${WINDOWS_IP}:3000" "White"
Write-ColorOutput "  Backend:  http://${WINDOWS_IP}:8545" "White"

Write-ColorOutput "`nWSL internal:" "Cyan"
Write-ColorOutput "  Frontend: http://${WSL_IP}:3000" "White"
Write-ColorOutput "  Backend:  http://${WSL_IP}:8545" "White"

# ============================================================
# Test suggestions
# ============================================================
Print-Header "🧪 Test suggestions"

Write-ColorOutput "1. Test local access:" "Yellow"
Write-ColorOutput "   Open in Windows browser: http://localhost:3000" "White"

Write-ColorOutput "`n2. Test LAN access:" "Yellow"
Write-ColorOutput "   Open on phone browser: http://${WINDOWS_IP}:3000" "White"

Write-ColorOutput "`n3. If phone can't access, check:" "Yellow"
Write-ColorOutput "   - Phone and PC on same Wi-Fi" "White"
Write-ColorOutput "   - Windows Firewall settings" "White"
Write-ColorOutput "   - Router AP isolation disabled" "White"

# ============================================================
# Important notes
# ============================================================
Print-Header "⚠️  Important notes"

Write-ColorOutput "1. WSL IP may change after restart; rerun this script." "Yellow"
Write-ColorOutput "2. Windows restart keeps rules but WSL IP can change." "Yellow"
Write-ColorOutput "3. To remove all rules, run cleanup-port-forwarding.ps1." "Yellow"

# ============================================================
# Done
# ============================================================
Print-Header "✨ Setup complete"

Write-ColorOutput "All port forwarding and firewall rules configured!" "Green"
Write-ColorOutput "`nPress any key to exit..." "Cyan"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
