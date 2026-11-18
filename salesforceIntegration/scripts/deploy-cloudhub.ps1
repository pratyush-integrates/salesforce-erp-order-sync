# Deploys one Mule app to CloudHub 2.0 and prints its public URL. Values come from the .env file at
# the repo root. Deploy the system APIs first, because the process API needs their hosts.
#
#   .\scripts\deploy-cloudhub.ps1 -Api salesforce-sys-api
param(
    [Parameter(Mandatory)][ValidateSet('salesforce-sys-api', 'erp-sys-api', 'order-process-api', 'order-status-exp-api')][string]$Api,
    [switch]$SkipTests,
    [switch]$SkipPublish
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$repo = Split-Path $root -Parent
$dir = if ($Api -eq 'order-process-api') { "$repo\$Api" } else { "$root\apis\$Api" }

Get-Content "$repo\.env" | Where-Object { $_ -match '^\s*[^#\s][^=]*=' } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), 'Process')
}
$env:SF_CLIENT_ID = ${env:salesforce.clientId}
$env:SF_CLIENT_SECRET = ${env:salesforce.clientSecret}
$env:SF_TOKEN_URL = ${env:salesforce.tokenUrl}
$env:API_ID = [Environment]::GetEnvironmentVariable("API_ID_$($Api -replace '-', '_')")
if (-not $env:API_ID) { throw "Set API_ID_$($Api -replace '-', '_') in .env" }

# Use Code Builder's JDK and Maven. Maven 3.10 cannot load the Mule plugin.
$acb = "$env:USERPROFILE\AnypointCodeBuilder"
$env:JAVA_HOME = (Get-ChildItem "$acb\java" -Directory | Sort-Object Name | Select-Object -Last 1).FullName
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$mvn = (Get-ChildItem "$env:USERPROFILE\.vscode\extensions\salesforce.mule-dx-dependencies-*\build\deps\apache-maven-*\bin\mvn.cmd" | Select-Object -Last 1).FullName

$common = @('-B', '-s', "$PSScriptRoot\maven-settings.xml", '-f', "$dir\pom.xml", '-Pcloudhub2')

# CloudHub pulls the app from Exchange, so it has to be published first. A version can only be
# published once, so a retry of the same version skips this step with -SkipPublish.
if (-not $SkipPublish) {
    $publish = $common + @('clean', 'deploy')
    if ($SkipTests) { $publish += '-DskipTests' }
    & $mvn @publish
    if ($LASTEXITCODE -ne 0) { throw "Publish failed: $Api" }
}

$deploy = $common + @('mule:deploy', '-DmuleDeploy')
& $mvn @deploy
if ($LASTEXITCODE -ne 0) { throw "Deploy failed: $Api" }
