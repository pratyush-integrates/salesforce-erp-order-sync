# Builds all four Mule apps and runs them together on one local runtime, with the mock ERP.
#
#   .\scripts\run-local.ps1                 Build, then run
#   .\scripts\run-local.ps1 -SkipBuild      Run the last build
#   .\scripts\run-local.ps1 -NoEvents       Run without the Salesforce event listener
#   .\scripts\run-local.ps1 -Tunnel         Reach the mock ERP through a public Cloudflare tunnel
#
# Salesforce credentials come from the .env file at the repo root (see .env.example). They are set
# as environment variables, so they never reach the repo or the logs.
param([switch]$SkipBuild, [switch]$NoEvents, [switch]$Tunnel)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$repo = Split-Path $root -Parent
$apis = @{
    'salesforce-sys-api' = "$root\apis\salesforce-sys-api"
    'erp-sys-api' = "$root\apis\erp-sys-api"
    'order-process-api' = "$repo\order-process-api"
    'order-status-exp-api' = "$root\apis\order-status-exp-api"
}

if (Test-Path "$repo\.env") {
    Get-Content "$repo\.env" | Where-Object { $_ -match '^\s*[^#\s][^=]*=' } | ForEach-Object {
        $name, $value = $_ -split '=', 2
        [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), 'Process')
    }
}

# Use Code Builder's JDK and Maven. Maven 3.10 cannot load the Mule plugin.
$acb = "$env:USERPROFILE\AnypointCodeBuilder"
$env:JAVA_HOME = (Get-ChildItem "$acb\java" -Directory | Sort-Object Name | Select-Object -Last 1).FullName
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$runtime = "$acb\runtime\mule-enterprise-standalone-4.12.3"
$mvn = (Get-ChildItem "$env:USERPROFILE\.vscode\extensions\salesforce.mule-dx-dependencies-*\build\deps\apache-maven-*\bin\mvn.cmd" | Select-Object -Last 1).FullName

if (-not $SkipBuild) {
    foreach ($api in $apis.Keys) {
        Write-Host "Building $api ..."
        & $mvn -B -q -f "$($apis[$api])\pom.xml" clean package -DskipTests
        if ($LASTEXITCODE -ne 0) { throw "Build failed: $api" }
    }
}

# A separate runtime folder, so Code Builder's own runtime stays untouched.
$base = "$root\.mule-local"
foreach ($dir in 'apps', 'domains', 'logs') { New-Item -ItemType Directory -Force "$base\$dir" | Out-Null }
foreach ($dir in 'conf', 'services', 'server-plugins') {
    if (-not (Test-Path "$base\$dir\*")) { Copy-Item "$runtime\$dir" $base -Recurse -Force }
}
# Clear earlier builds, so an app that has been renamed doesn't deploy twice and clash on its port.
Remove-Item "$base\apps\*" -Recurse -Force
foreach ($api in $apis.Keys) { Copy-Item "$($apis[$api])\target\$api-app-1.0.0-mule-application.jar" "$base\apps\" -Force }
# Mule saves each flow's stopped state and prefers it over initialState, so a -NoEvents run would
# otherwise leave the event listener off for every later run.
Remove-Item "$base\.mule\*\deployment-properties\flows.deployment.properties" -Force -ErrorAction SilentlyContinue

# Four apps need more class memory than the default 256 MB. mule.bat drops the value of
# -M-Dname=value flags on Windows, so JVM settings go through this variable. The JVM prints it
# at startup, which is why credentials must not go here.
$options = '-XX:MaxMetaspaceSize=1024m -Xmx2048m'
# There are no platform credentials locally, so the gateway would answer every request with 503.
$options += ' -Danypoint.platform.gatekeeper=disabled'
if ($NoEvents) { $options += ' -DorderEvents.initialState=stopped' }
$env:_JAVA_OPTIONS = $options
$env:MULE_BASE = $base

# The mock reads ERP_API_KEY and ERP_API_SECRET from the environment, so erp-sys-api has to send the same ones.
if ($env:ERP_API_KEY) {
    [Environment]::SetEnvironmentVariable('erp.apiKey', $env:ERP_API_KEY, 'Process')
    [Environment]::SetEnvironmentVariable('erp.apiSecret', $env:ERP_API_SECRET, 'Process')
}

# Replace any mock left over from an earlier run, because its data and API key may be out of date.
Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
Start-Process node -ArgumentList "`"$root\mock-erp\server.mjs`"" -WindowStyle Hidden -RedirectStandardOutput "$base\logs\mock-erp.log"
Write-Host "Mock ERP started on 8090. Requests are logged to $base\logs\mock-erp.log"

if ($Tunnel) {
    # A quick tunnel needs no Cloudflare account. It gets a new URL on every start.
    Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
    # A new log for each run, because an old one holds the URL of a tunnel that no longer exists.
    $tunnelLog = "$base\logs\cloudflared-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    Start-Process cloudflared -ArgumentList 'tunnel', '--no-autoupdate', '--url', 'http://localhost:8090', '--logfile', "`"$tunnelLog`"" -WindowStyle Hidden
    $tunnelHost = $null
    $deadline = (Get-Date).AddSeconds(60)
    while (-not $tunnelHost -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if (Test-Path $tunnelLog) { $tunnelHost = ([regex]::Match((Get-Content $tunnelLog -Raw), '[a-z0-9-]+\.trycloudflare\.com')).Value }
    }
    if (-not $tunnelHost) { throw "The tunnel gave no URL within 60 seconds. See $tunnelLog" }
    [Environment]::SetEnvironmentVariable('erp.protocol', 'HTTPS', 'Process')
    [Environment]::SetEnvironmentVariable('erp.host', $tunnelHost, 'Process')
    [Environment]::SetEnvironmentVariable('erp.port', '443', 'Process')
    Set-Content "$base\logs\tunnel-url.txt" "https://$tunnelHost" -Encoding Ascii
    Write-Host "Tunnel open: https://$tunnelHost -> mock ERP"
}

Write-Host 'Starting Mule, which takes about a minute. Press Ctrl+C to stop.'
Write-Host "App logs: $base\logs"
# The JVM writes a harmless "Picked up _JAVA_OPTIONS" line to stderr, which Stop would treat as fatal.
$ErrorActionPreference = 'Continue'
& "$runtime\bin\mule.bat"
