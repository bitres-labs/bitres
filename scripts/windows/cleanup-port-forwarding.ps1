# BRS system - WSL port forwarding cleanup
# Removes all port forwarding and firewall rules
# Usage: Run in PowerShell as Administrator

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
Print-Header "🧹 BRS system - port forwarding cleanup"

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
$PORTS = @(8545, 3000)
$FIREWALL_RULES = @("BRS-Hardhat-TCP-8545", "BRS-Frontend-TCP-3000")

# Confirm cleanup
Write-ColorOutput "⚠️  Warning: This will remove all BRS port forwarding and firewall rules" "Yellow"
Write-ColorOutput "Continue? (Y/N): " "Yellow" -NoNewline
$confirm = Read-Host
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-ColorOutput "`nCancelled" "Yellow"
    exit 0
}

# ============================================================
# Step 1: Remove port forwarding rules
# ============================================================
Print-Header "Step 1/2: Remove port forwarding rules"

foreach ($port in $PORTS) {
    Write-ColorOutput "Removing port forwarding for port $port..." "White"

    try {
        $existingRule = netsh interface portproxy show v4tov4 | Select-String "0.0.0.0.*$port"
        if ($existingRule) {
            netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 | Out-Null
            Write-ColorOutput "  ✅ Port $port forwarding removed" "Green"
        } else {
            Write-ColorOutput "  ℹ️  No forwarding rule for port $port" "Gray"
        }
    } catch {
        Write-ColorOutput "  ❌ Failed to remove port $port rule: $($_.Exception.Message)" "Red"
    }
}

Write-ColorOutput "`n✅ Port forwarding cleanup complete`n" "Green"

# ============================================================
# Step 2: Remove firewall rules
# ============================================================
Print-Header "Step 2/2: Remove firewall rules"

foreach ($ruleName in $FIREWALL_RULES) {
    Write-ColorOutput "Removing firewall rule: $ruleName..." "White"

    try {
        $existingRule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
        if ($existingRule) {
            Remove-NetFirewallRule -Name $ruleName
            Write-ColorOutput "  ✅ Firewall rule removed: $ruleName" "Green"
        } else {
            Write-ColorOutput "  ℹ️  Firewall rule not found: $ruleName" "Gray"
        }
    } catch {
        Write-ColorOutput "  ❌ Failed to remove firewall rule: $($_.Exception.Message)" "Red"
    }
}

Write-ColorOutput "`n✅ Firewall cleanup complete`n" "Green"

# ============================================================
# Show remaining config
# ============================================================
Print-Header "📋 Remaining port forwarding config"

$remainingRules = netsh interface portproxy show v4tov4
if ($remainingRules) {
    Write-ColorOutput "Remaining port forwarding rules:" "Cyan"
    netsh interface portproxy show v4tov4
} else {
    Write-ColorOutput "✅ All port forwarding rules removed" "Green"
}

# ============================================================
# Done
# ============================================================
Print-Header "✨ Cleanup complete"

Write-ColorOutput "All BRS port forwarding and firewall rules have been removed!" "Green"
Write-ColorOutput "`nPress any key to exit..." "Cyan"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
