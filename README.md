# DHCP MAC Lookup

A small PowerShell GUI tool that finds a machine's MAC address from a Windows DHCP server by hostname, searching **every scope** on the server in one go.

> **Disclaimer:** This project was entirely vibe-coded with [Claude](https://claude.ai). I wrote none of the code myself and take no credit for it. It has been tested only as far as I've personally tried it, so review it and use it at your own risk.

## Features

- Searches all IPv4 scopes on the DHCP server, not just one scope ID
- Simple Windows Forms GUI: enter a server and hostname, click **Search**
- Results grid shows MAC address, hostname, IP address and scope name
- MAC addresses are shown **lowercase and colon-separated** (`00:11:22:33:44:55`) rather than the dash-separated format DHCP returns
- **Copy MAC** button copies the selected MAC to the clipboard
- Self-elevates: if not run as Administrator, it relaunches itself with a UAC prompt

## Requirements

- Windows with PowerShell 5.1 or later
- RSAT: DHCP Server Tools (provides the `DhcpServer` module)
- Permission to read leases on the target DHCP server

## Usage

1. Download `Get-DhcpMac.ps1`.
2. Right-click it and choose **Run with PowerShell**, or run:

   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Get-DhcpMac.ps1
   ```

3. Accept the UAC prompt if you are not already elevated.
4. Enter the DHCP server name.
5. Enter a hostname and click **Search** (or press Enter).

### Hostname matching

| Input | Matches |
| --- | --- |
| `office-pc-001.somedomain.com` | That exact hostname |
| `office-pc-001` | The short name plus any domain suffix |
| `office-pc-*` | Wildcards (`*` and `?`) are supported |

## How it works

The script runs `Get-DhcpServerv4Scope` to list all scopes, then `Get-DhcpServerv4Lease -AllLeases` against each one, filtering on `HostName`. Servers with many scopes take longer, and the status line shows progress.
