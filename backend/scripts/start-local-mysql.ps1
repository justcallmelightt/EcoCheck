# A separate local MySQL instance. Does not change the installed MySQL80 service.
param([string]$MySqlBin = '', [int]$Port = 33316)
$ErrorActionPreference = 'Stop'
if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Choose a port between 1024 and 65535.' }
if (!$MySqlBin) {
    $serverDir = Get-ChildItem -Path 'C:\Program Files\MySQL' -Directory -Filter 'MySQL Server *' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (!$serverDir) { throw 'Install MySQL Server 8.0+ or pass -MySqlBin with its bin directory.' }
    $MySqlBin = Join-Path $serverDir.FullName 'bin'
}
$serverExe = Join-Path $MySqlBin 'mysqld.exe'
$adminExe = Join-Path $MySqlBin 'mysqladmin.exe'
if (!(Test-Path -LiteralPath $serverExe) -or !(Test-Path -LiteralPath $adminExe)) { throw 'MySQL bin directory is invalid.' }
$backendDir = Split-Path $PSScriptRoot -Parent
$localDir = Join-Path $backendDir '.data'
$dataDir = Join-Path $localDir 'mysql'
$envPath = Join-Path $backendDir '.env'
$configPath = Join-Path $localDir 'my.ini'
$adminPath = Join-Path $localDir 'admin.cnf'
$initPath = Join-Path $localDir 'init.sql'
$statePath = Join-Path $localDir 'instance.json'
New-Item -ItemType Directory -Force -Path $localDir | Out-Null
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.port -ne $Port) { throw 'This local instance was created on a different port. Use that port.' }
    & $adminExe "--defaults-extra-file=$adminPath" ping --silent 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "Local EcoCheck MySQL is already running on 127.0.0.1:$Port"; exit 0 }
} elseif ((Test-Path -LiteralPath $envPath) -or (Test-Path -LiteralPath $dataDir)) {
    throw 'Existing .env or data found. Keep it and configure your own DB, or use a fresh checkout for the local helper.'
}
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
try { $listener.Start() } catch { throw "Port $Port is already in use. No existing server was changed." } finally { $listener.Stop() }
if (!(Test-Path -LiteralPath $statePath)) {
    $appSecret = ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))
    $rootSecret = ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))
    $sql = @"
CREATE DATABASE IF NOT EXISTS ecocheck CHARACTER SET utf8mb4;
CREATE DATABASE IF NOT EXISTS ecocheck_test CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 'ecocheck'@'127.0.0.1' IDENTIFIED BY '$appSecret';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, REFERENCES ON ecocheck.* TO 'ecocheck'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, REFERENCES ON ecocheck_test.* TO 'ecocheck'@'127.0.0.1';
ALTER USER 'root'@'localhost' IDENTIFIED BY '$rootSecret';
"@
    [IO.File]::WriteAllText($initPath, $sql)
    [IO.File]::WriteAllText($adminPath, "[client]`nhost=127.0.0.1`nport=$Port`nuser=root`npassword=$rootSecret`n")
    [IO.File]::WriteAllText($envPath, "ECOCHECK_HOST=127.0.0.1`nECOCHECK_PORT=8080`nECOCHECK_DB_URL=jdbc:mysql://127.0.0.1:$Port/ecocheck?connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true&characterEncoding=UTF-8&connectTimeout=5000&socketTimeout=5000`nECOCHECK_DB_USER=ecocheck`nECOCHECK_DB_PASSWORD=$appSecret`n")
    $initProcess = Start-Process -FilePath $serverExe -ArgumentList @('--initialize-insecure', "--datadir=`"$dataDir`"") -WindowStyle Hidden -PassThru -Wait
    if ($initProcess.ExitCode -ne 0) { throw 'MySQL initialization failed. Check .data/mysql/*.err. Keep the generated files for diagnosis.' }
}
$normalizedData = $dataDir.Replace('\','/')
$normalizedInit = $initPath.Replace('\','/')
$initOption = if (Test-Path -LiteralPath $initPath) { "init-file=`"$normalizedInit`"`n" } else { '' }
[IO.File]::WriteAllText($configPath, "[mysqld]`ndatadir=`"$normalizedData`"`nbind-address=127.0.0.1`nport=$Port`nmysqlx=0`n$initOption")
$process = Start-Process -FilePath $serverExe -ArgumentList "--defaults-file=`"$configPath`"" -WindowStyle Hidden -PassThru
$ready = $false
for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 500
    if ($process.HasExited) { throw 'MySQL stopped during startup. Check .data/mysql/*.err.' }
    & $adminExe "--defaults-extra-file=$adminPath" ping --silent 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
}
if (!$ready) { throw 'MySQL did not become ready. Check .data/mysql/*.err.' }
# Remove only the known bootstrap file after successful authentication.
if (Test-Path -LiteralPath $initPath) { Remove-Item -LiteralPath $initPath }
[IO.File]::WriteAllText($configPath, "[mysqld]`ndatadir=`"$normalizedData`"`nbind-address=127.0.0.1`nport=$Port`nmysqlx=0`n")
@{port=$Port; bin=$MySqlBin} | ConvertTo-Json | Set-Content -LiteralPath $statePath
Write-Host "Local EcoCheck MySQL is ready on 127.0.0.1:$Port. backend/.env was prepared."
