Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Managed host list.
$managedDomains = @(
  "hfeshell.nscc-hf.cn"
  "wuzh01.hpccube.com"
  "wuzh02.hpccube.com"
  "tycs1.hpccube.com"
  "tycs2.hpccube.com"
  "www.scnet.cn"
)

# First-run route baseline.
$initialManagedRoutes = @(
  "112.122.7.132/32"
  "183.162.233.194/32"
  "112.11.77.146/32"
  "1.71.171.15/32"
  "8.217.241.78/32"
  "8.210.227.132/32"
  "39.184.160.166/32"
  "218.26.3.67/32"
)

$routingKey = "flutter.routing_settings_iwan.ustc"
$configPath = Join-Path $env:APPDATA "com.panabit\panabit_client\shared_preferences.json"
$dataRoot = Join-Path $env:LOCALAPPDATA "update_iwan_routes"
$statePath = Join-Path $dataRoot "state.json"
$backupDir = Join-Path $dataRoot "backups"

# Status output.
function Write-Status {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $color = switch ($Label) {
    "OK" { "Green" }
    "SKIP" { "Yellow" }
    "ERROR" { "Red" }
    "DRY-RUN" { "Cyan" }
    default { "Gray" }
  }

  Write-Host "[" -NoNewline
  Write-Host $Label -ForegroundColor $color -NoNewline
  Write-Host "] $Message"
}

# CLI help.
function Show-Usage {
  Write-Output @"
Usage: update_iwan_routes [--dry-run|--run]

Resolve cluster IPv4 addresses and update Panabit iWAN routes.

Options:
  --dry-run   Show route changes only. Default.
  --run       Back up and update the iWAN route setting.
  -h, --help  Show this help.
"@
}

# Stable deduplication.
function Get-UniqueList {
  param([Parameter(Mandatory = $true)][object[]]$Items)

  $seen = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  $result = New-Object "System.Collections.Generic.List[string]"

  foreach ($item in $Items) {
    $value = [string]$item
    if ($seen.Add($value)) {
      [void]$result.Add($value)
    }
  }

  return $result.ToArray()
}

# Route parsing.
function ConvertTo-RouteList {
  param([AllowEmptyString()][string]$RouteText)

  if ([string]::IsNullOrWhiteSpace($RouteText)) {
    return @()
  }

  $routes = @(
    $RouteText.Split(",") |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ -ne "" }
  )

  return @(Get-UniqueList -Items $routes)
}

# Panabit config reader.
function Read-IwanConfig {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "iWAN config not found: $Path"
  }

  $content = [System.IO.File]::ReadAllText($Path)

  try {
    $outer = $content | ConvertFrom-Json
  } catch {
    throw "Invalid iWAN config JSON: $Path"
  }

  $property = $outer.PSObject.Properties[$routingKey]
  if ($null -eq $property -or -not ($property.Value -is [string])) {
    throw "iWAN routing setting not found: $routingKey"
  }

  try {
    $routing = $property.Value | ConvertFrom-Json
  } catch {
    throw "Invalid nested iWAN routing setting."
  }

  $modeProperty = $routing.PSObject.Properties["mode"]
  $routesProperty = $routing.PSObject.Properties["custom_routes"]
  if ($null -eq $modeProperty -or $modeProperty.Value -ne "custom") {
    throw "iWAN is not using custom routes. Select '按网段路由' first."
  }
  if ($null -eq $routesProperty -or -not ($routesProperty.Value -is [string])) {
    throw "iWAN custom_routes setting not found."
  }

  $routePattern = [regex]'\\"custom_routes\\":\\"([^"\\]*)\\"'
  $matches = $routePattern.Matches($content)
  if ($matches.Count -ne 1) {
    throw "Expected one custom_routes field, found $($matches.Count)."
  }

  return [pscustomobject]@{
    Content = $content
    RouteText = [string]$routesProperty.Value
    Routes = @(ConvertTo-RouteList -RouteText ([string]$routesProperty.Value))
  }
}

# Managed route state.
function Read-ManagedState {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return [pscustomobject]@{
      Exists = $false
      Routes = @($initialManagedRoutes)
      Content = $null
    }
  }

  $content = [System.IO.File]::ReadAllText($Path)
  try {
    $state = $content | ConvertFrom-Json
  } catch {
    throw "Invalid route state JSON: $Path"
  }

  $property = $state.PSObject.Properties["managed_routes"]
  if ($null -eq $property) {
    throw "managed_routes missing from state: $Path"
  }

  $routes = @($property.Value | ForEach-Object { [string]$_ })
  foreach ($route in $routes) {
    if ($route -notmatch '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/32$') {
      throw "Invalid managed route in state: $route"
    }
  }

  return [pscustomobject]@{
    Exists = $true
    Routes = @(Get-UniqueList -Items $routes)
    Content = $content
  }
}

# DNS lookup.
function Resolve-ManagedRoutes {
  $routes = New-Object "System.Collections.Generic.List[string]"
  $rows = New-Object "System.Collections.Generic.List[object]"

  foreach ($domain in $managedDomains) {
    try {
      $answers = @(
        Resolve-DnsName -Name $domain -Type A -DnsOnly -ErrorAction Stop |
          Where-Object {
            $_.Section -eq "Answer" -and
            $_.Type -eq "A" -and
            -not [string]::IsNullOrWhiteSpace([string]$_.IPAddress)
          }
      )
    } catch {
      throw "DNS lookup failed: $domain"
    }

    $addresses = @(
      $answers |
        ForEach-Object { [string]$_.IPAddress } |
        Sort-Object -Unique
    )

    if ($addresses.Count -eq 0) {
      throw "No IPv4 answer found: $domain"
    }

    foreach ($address in $addresses) {
      $parsedAddress = $null
      if (-not [System.Net.IPAddress]::TryParse($address, [ref]$parsedAddress) -or
          $parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Invalid IPv4 answer for ${domain}: $address"
      }

      [void]$routes.Add("$address/32")
    }

    [void]$rows.Add([pscustomobject]@{
      Domain = $domain
      Addresses = $addresses
    })
  }

  return [pscustomobject]@{
    Routes = @(Get-UniqueList -Items ($routes.ToArray()))
    Rows = @($rows.ToArray())
  }
}

# Preserve extra routes.
function Merge-Routes {
  param(
    [Parameter(Mandatory = $true)][object[]]$CurrentRoutes,
    [Parameter(Mandatory = $true)][object[]]$OldManagedRoutes,
    [Parameter(Mandatory = $true)][object[]]$NewManagedRoutes
  )

  $oldSet = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($route in $OldManagedRoutes) {
    [void]$oldSet.Add([string]$route)
  }

  $merged = New-Object "System.Collections.Generic.List[string]"
  foreach ($route in $CurrentRoutes) {
    if (-not $oldSet.Contains([string]$route)) {
      [void]$merged.Add([string]$route)
    }
  }
  foreach ($route in $NewManagedRoutes) {
    [void]$merged.Add([string]$route)
  }

  return @(Get-UniqueList -Items ($merged.ToArray()))
}

# Route diff.
function Get-ChangedRoutes {
  param(
    [Parameter(Mandatory = $true)][object[]]$Left,
    [Parameter(Mandatory = $true)][object[]]$Right
  )

  $rightSet = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($route in $Right) {
    [void]$rightSet.Add([string]$route)
  }

  return @($Left | Where-Object { -not $rightSet.Contains([string]$_) })
}

# Minimal config edit.
function New-UpdatedConfigContent {
  param(
    [Parameter(Mandatory = $true)][string]$Content,
    [AllowEmptyString()][string]$NewRouteText
  )

  $routePattern = [regex]'\\"custom_routes\\":\\"([^"\\]*)\\"'
  $matches = $routePattern.Matches($Content)
  if ($matches.Count -ne 1) {
    throw "Expected one custom_routes field, found $($matches.Count)."
  }

  $replacement = '\"custom_routes\":\"' + $NewRouteText + '\"'
  return $routePattern.Replace($Content, $replacement, 1)
}

# UTF-8 writer.
function Write-Utf8NoBom {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )

  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

# Atomic file replace.
function Replace-FileAtomic {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )

  $directory = Split-Path -Parent $Path
  $tempPath = Join-Path $directory ("." + [System.IO.Path]::GetRandomFileName())

  try {
    Write-Utf8NoBom -Path $tempPath -Content $Content
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
      [System.IO.File]::Replace($tempPath, $Path, $null)
    } else {
      [System.IO.File]::Move($tempPath, $Path)
    }
  } finally {
    if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
      Remove-Item -LiteralPath $tempPath -Force
    }
  }
}

# Route-only backup.
function Write-RouteBackup {
  param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][string]$CurrentRouteText,
    [Parameter(Mandatory = $true)][object[]]$OldManagedRoutes,
    [Parameter(Mandatory = $true)][object[]]$NewManagedRoutes
  )

  [void][System.IO.Directory]::CreateDirectory($Directory)
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
  $path = Join-Path $Directory "routes_$stamp.json"
  $backup = [ordered]@{
    saved_at = (Get-Date).ToString("o")
    previous_routes = $CurrentRouteText
    previous_managed_routes = @($OldManagedRoutes)
    new_managed_routes = @($NewManagedRoutes)
  } | ConvertTo-Json -Depth 4

  Write-Utf8NoBom -Path $path -Content $backup
  return $path
}

# Managed state writer.
function Write-ManagedState {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object[]]$Routes
  )

  $directory = Split-Path -Parent $Path
  [void][System.IO.Directory]::CreateDirectory($directory)
  $state = [ordered]@{
    updated_at = (Get-Date).ToString("o")
    managed_routes = @($Routes)
  } | ConvertTo-Json -Depth 3

  Replace-FileAtomic -Path $Path -Content $state
}

# iWAN process guard.
function Test-IwanStopped {
  return $null -eq (Get-Process -Name "mobile_client" -ErrorAction SilentlyContinue)
}

# Main workflow.
function Invoke-Main {
  param([object[]]$CliArgs)

  $mode = "dry-run"
  $modeSeen = $false
  foreach ($argValue in $CliArgs) {
    $arg = [string]$argValue
    switch ($arg) {
      "--dry-run" {
        if ($modeSeen) { throw "Choose only one mode: --dry-run or --run." }
        $mode = "dry-run"
        $modeSeen = $true
      }
      "--run" {
        if ($modeSeen) { throw "Choose only one mode: --dry-run or --run." }
        $mode = "run"
        $modeSeen = $true
      }
      { $_ -in @("-h", "--help") } {
        Show-Usage
        return
      }
      default {
        throw "Unknown option: $arg"
      }
    }
  }

  $config = Read-IwanConfig -Path $configPath
  $state = Read-ManagedState -Path $statePath
  $resolved = Resolve-ManagedRoutes
  $newRoutes = @(Merge-Routes -CurrentRoutes $config.Routes -OldManagedRoutes $state.Routes -NewManagedRoutes $resolved.Routes)
  $newRouteText = $newRoutes -join ","
  $added = @(Get-ChangedRoutes -Left $newRoutes -Right $config.Routes)
  $removed = @(Get-ChangedRoutes -Left $config.Routes -Right $newRoutes)
  $changed = $added.Count -gt 0 -or $removed.Count -gt 0
  if (-not $changed) {
    $newRoutes = @($config.Routes)
    $newRouteText = $config.RouteText
  }

  Write-Host ""
  Write-Host "iWAN route update" -ForegroundColor Cyan
  Write-Host "Target: $configPath"
  Write-Host "Mode: $mode"
  Write-Host "Rule: managed IPv4 /32; preserve other routes"
  if ($mode -eq "dry-run") {
    Write-Status -Label "DRY-RUN" -Message "No iWAN settings will be changed."
  }
  Write-Host ""

  foreach ($row in $resolved.Rows) {
    Write-Host ("{0}: {1}" -f $row.Domain, ($row.Addresses -join ", "))
  }

  Write-Host ""
  Write-Host "Added: $(if ($added.Count -eq 0) { '(none)' } else { $added -join ',' })"
  Write-Host "Removed: $(if ($removed.Count -eq 0) { '(none)' } else { $removed -join ',' })"
  Write-Host "Routes: $newRouteText"
  Write-Host ""

  if (-not $changed) {
    Write-Status -Label "SKIP" -Message "Routes are already current."
    return
  }

  if ($mode -eq "dry-run") {
    Write-Status -Label "OK" -Message "Dry run completed. Add --run to update iWAN."
    return
  }

  if (-not (Test-IwanStopped)) {
    throw "Panabit iWAN is running. Exit it from the system tray, then run again."
  }

  $updatedContent = New-UpdatedConfigContent -Content $config.Content -NewRouteText $newRouteText
  $backupPath = Write-RouteBackup -Directory $backupDir -CurrentRouteText $config.RouteText -OldManagedRoutes $state.Routes -NewManagedRoutes $resolved.Routes

  $configWritten = $false
  try {
    Replace-FileAtomic -Path $configPath -Content $updatedContent
    $configWritten = $true

    $verified = Read-IwanConfig -Path $configPath
    if ($verified.RouteText -ne $newRouteText) {
      throw "Updated route verification failed."
    }

    Write-ManagedState -Path $statePath -Routes $resolved.Routes
  } catch {
    $updateError = $_.Exception.Message
    if ($configWritten) {
      try {
        Replace-FileAtomic -Path $configPath -Content $config.Content
      } catch {
        throw "Update failed: $updateError; config rollback also failed. Backup: $backupPath"
      }
    }
    throw "Update failed and config was restored: $updateError"
  }

  Write-Status -Label "OK" -Message "iWAN routes updated."
  Write-Host "Backup: $backupPath"
  Write-Host "Restart Panabit iWAN to load the new routes."
}

# Direct execution only.
if ($MyInvocation.InvocationName -ne ".") {
  try {
    Invoke-Main -CliArgs $args
  } catch {
    Write-Status -Label "ERROR" -Message $_.Exception.Message
    if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
      Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    exit 1
  }
}
