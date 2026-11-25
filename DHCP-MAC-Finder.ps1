#Requires -Version 5.1
<#
.SYNOPSIS
    GUI tool: look up a hostname's MAC address across ALL scopes on a DHCP server.
    Self-elevates if not run as Administrator. MAC is shown colon-separated.
#>

# ---- Self-elevate -----------------------------------------------------------
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $exe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    Start-Process -FilePath $exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', "`"$PSCommandPath`""
    )
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
    [System.Windows.Forms.MessageBox]::Show(
        "The DhcpServer PowerShell module is missing.`nInstall the RSAT DHCP Server tools and try again.",
        'Missing module', 'OK', 'Error') | Out-Null
    exit 1
}
Import-Module DhcpServer

# ---- UI ---------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'DHCP MAC Lookup'
$form.Size            = New-Object System.Drawing.Size(1120, 420)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false

function New-Label($text, $x, $y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.AutoSize = $true; $l.Location = New-Object System.Drawing.Point($x, $y)
    $form.Controls.Add($l); $l
}

New-Label 'DHCP server:' 15 18 | Out-Null
$txtServer = New-Object System.Windows.Forms.TextBox
$txtServer.Location = New-Object System.Drawing.Point(110, 15)
$txtServer.Size     = New-Object System.Drawing.Size(980, 23)
$form.Controls.Add($txtServer)

New-Label 'Hostname:' 15 52 | Out-Null
$txtHost = New-Object System.Windows.Forms.TextBox
$txtHost.Location = New-Object System.Drawing.Point(110, 49)
$txtHost.Size     = New-Object System.Drawing.Size(880, 23)
$form.Controls.Add($txtHost)

New-Label 'IP address:' 15 86 | Out-Null
$txtIP = New-Object System.Windows.Forms.TextBox
$txtIP.Location = New-Object System.Drawing.Point(110, 83)
$txtIP.Size     = New-Object System.Drawing.Size(880, 23)
$form.Controls.Add($txtIP)

$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Text     = 'Search'
$btnSearch.Location = New-Object System.Drawing.Point(1000, 64)
$btnSearch.Size     = New-Object System.Drawing.Size(90, 27)
$form.Controls.Add($btnSearch)
$form.AcceptButton = $btnSearch

$lblStatus = New-Label 'Ready.' 15 118

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(15, 143)
$grid.Size     = New-Object System.Drawing.Size(1075, 187)
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.RowHeadersVisible  = $false
$grid.SelectionMode      = 'FullRowSelect'
$grid.AutoSizeColumnsMode = 'Fill'
$grid.BackgroundColor    = [System.Drawing.SystemColors]::Window
foreach ($c in 'MAC Address','HostName','IP Address','Scope Name') { $grid.Columns.Add($c, $c) | Out-Null }
$form.Controls.Add($grid)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text     = 'Copy MAC'
$btnCopy.Location = New-Object System.Drawing.Point(15, 342)
$btnCopy.Size     = New-Object System.Drawing.Size(110, 28)
$btnCopy.Enabled  = $false
$form.Controls.Add($btnCopy)

# ---- Logic ------------------------------------------------------------------
$btnSearch.Add_Click({
    $server = $txtServer.Text.Trim()
    $name   = $txtHost.Text.Trim()
    $ip     = $txtIP.Text.Trim()
    if (-not $server -or (-not $name -and -not $ip)) {
        [System.Windows.Forms.MessageBox]::Show('Enter a DHCP server and a hostname and/or an IP address.') | Out-Null
        return
    }
    # No wildcard given -> match the exact name, or the short name followed by a domain
    $pattern = $name
    $short   = ($name -split '\.')[0]
    $criteria = (@(if ($name) { "'$name'" }; if ($ip) { "'$ip'" }) -join ' / ')

    $grid.Rows.Clear()
    $btnCopy.Enabled  = $false
    $btnSearch.Enabled = $false
    $form.Cursor = 'WaitCursor'
    try {
        $lblStatus.Text = "Getting scopes from $server ..."; $form.Refresh()
        $scopes = @(Get-DhcpServerv4Scope -ComputerName $server -ErrorAction Stop)

        $i = 0
        foreach ($scope in $scopes) {
            $i++
            $lblStatus.Text = "Scope $i of $($scopes.Count): $($scope.ScopeId) ..."
            [System.Windows.Forms.Application]::DoEvents()

            $leases = Get-DhcpServerv4Lease -ComputerName $server -ScopeId $scope.ScopeId `
                        -AllLeases -ErrorAction SilentlyContinue |
                      Where-Object {
                          # Each filled-in box must match; an empty box is ignored
                          (-not $name -or $_.HostName -like $pattern -or
                              ($name -notmatch '\.' -and $_.HostName -like "$short.*")) -and
                          (-not $ip -or $_.IPAddress.ToString() -like $ip)
                      }
            foreach ($l in $leases) {
                $mac = ($l.ClientId -replace '-', ':').ToLower()
                $grid.Rows.Add($mac, $l.HostName, $l.IPAddress, $scope.Name) | Out-Null
            }
        }

        if ($grid.Rows.Count -gt 0) {
            $lblStatus.Text = "Found $($grid.Rows.Count) match(es) across $($scopes.Count) scopes."
            $grid.Rows[0].Selected = $true
            $btnCopy.Enabled = $true
        } else {
            $lblStatus.Text = "No lease found for $criteria in $($scopes.Count) scopes."
        }
    }
    catch {
        $lblStatus.Text = 'Error.'
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Error', 'OK', 'Error') | Out-Null
    }
    finally {
        $form.Cursor = 'Default'
        $btnSearch.Enabled = $true
    }
})

$btnCopy.Add_Click({
    if ($grid.SelectedRows.Count -gt 0) {
        [System.Windows.Forms.Clipboard]::SetText([string]$grid.SelectedRows[0].Cells[0].Value)
        $lblStatus.Text = 'MAC copied to clipboard.'
    }
})

[void]$form.ShowDialog()
