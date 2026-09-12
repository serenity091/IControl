$ErrorActionPreference = 'Stop'
$ruleName = 'IControl-Local-WiFi-8080'
if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $ruleName -DisplayName 'IControl local Wi-Fi controllers' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080 -Profile Private -RemoteAddress LocalSubnet
}
