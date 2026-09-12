$ErrorActionPreference = 'Stop'
$ruleName = 'IControl-Local-WiFi-8080'
if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $ruleName -DisplayName 'IControl local Wi-Fi controllers' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080 -Profile Private -RemoteAddress LocalSubnet
}

# Dismissing Windows' first-run firewall prompt can create a program block that
# overrides the port allowance. Repair only generated private TCP blocks for
# this copy of IControl; leave public-network and unrelated application rules alone.
$appPaths = @(
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'dist\IControl.exe')),
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'IControl.exe'))
)
Get-NetFirewallRule -Enabled True -Direction Inbound -Action Block | Where-Object {
    $_.Name -like 'TCP Query User*' -and $_.Profile.ToString() -eq 'Private'
} | ForEach-Object {
    $block = $_
    $program = ($block | Get-NetFirewallApplicationFilter).Program
    $protocol = ($block | Get-NetFirewallPortFilter).Protocol
    if ($program -in $appPaths -and $protocol -eq 'TCP') {
        Disable-NetFirewallRule -InputObject $block
    }
}
