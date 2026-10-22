$ErrorActionPreference = 'Stop'
$localDir = Join-Path (Split-Path $PSScriptRoot -Parent) '.data'
$statePath = Join-Path $localDir 'instance.json'
if (!(Test-Path -LiteralPath $statePath)) { throw 'No local EcoCheck MySQL instance is configured.' }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$adminExe = Join-Path $state.bin 'mysqladmin.exe'
& $adminExe "--defaults-extra-file=$(Join-Path $localDir 'admin.cnf')" shutdown
if ($LASTEXITCODE -ne 0) { throw 'Local MySQL shutdown failed. The installed MySQL80 service was not changed.' }
Write-Host "Stopped the local EcoCheck MySQL instance on port $($state.port)."
