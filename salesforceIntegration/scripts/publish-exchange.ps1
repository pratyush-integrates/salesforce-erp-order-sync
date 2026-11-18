# Publishes the four OpenAPI specs to Anypoint Exchange.
#
# Create a Connected App in Anypoint (Access Management) with the Exchange Contributor scope, then:
#   $env:ANYPOINT_CLIENT_ID = '...'; $env:ANYPOINT_CLIENT_SECRET = '...'; $env:ANYPOINT_ORG = '...'
#   .\scripts\publish-exchange.ps1
$ErrorActionPreference = 'Stop'
foreach ($name in 'ANYPOINT_CLIENT_ID', 'ANYPOINT_CLIENT_SECRET', 'ANYPOINT_ORG') {
    if (-not [Environment]::GetEnvironmentVariable($name)) { throw "Set $name first" }
}
$specs = Join-Path (Split-Path $PSScriptRoot -Parent) 'specs'

foreach ($file in Get-ChildItem "$specs\*.yaml") {
    # The Mule app takes the plain name in Exchange, because CloudHub deploys it from there.
    $asset = "$($file.BaseName)-spec"
    $spec = Get-Content $file.FullName -Raw
    $title = [regex]::Match($spec, '(?m)^\s*title:\s*(.+)$').Groups[1].Value.Trim()
    Write-Host "Publishing $asset ..."
    # Windows PowerShell strips double quotes from native arguments unless they are escaped.
    $properties = '{\"apiVersion\":\"v1\",\"mainFile\":\"' + $file.Name + '\"}'
    $files = '{\"oas.yaml\":\"' + ($file.FullName -replace '\\', '/') + '\"}'
    & anypoint-cli-v4 exchange asset upload "$asset/1.0.0" --organization $env:ANYPOINT_ORG --name $title --type rest-api --properties $properties --files $files
    if ($LASTEXITCODE -ne 0) { throw "Could not publish $asset" }
}
