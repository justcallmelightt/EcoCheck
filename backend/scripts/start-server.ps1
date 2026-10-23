param(
    [switch]$Build,
    [switch]$Lan,
    [ValidateRange(1024,65535)][int]$Port=8080
)
$ErrorActionPreference='Stop'
$backend=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$java=Get-Command java.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if(-not $java -and $env:JAVA_HOME){$candidate=Join-Path $env:JAVA_HOME 'bin/java.exe';if(Test-Path $candidate){$java=$candidate}}
if(-not $java){
    $java=Get-ChildItem (Join-Path $env:ProgramFiles 'Java') -Directory -Filter 'jdk-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | ForEach-Object {Join-Path $_.FullName 'bin/java.exe'} |
        Where-Object {Test-Path $_} | Select-Object -First 1
}
if(-not $java){throw 'Install JDK 17 or newer, or set JAVA_HOME.'}
$jar=Join-Path $backend 'target/ecocheck-server-0.1.0.jar'
$previousHost=$env:ECOCHECK_HOST
$previousPort=$env:ECOCHECK_PORT
$previousJavaHome=$env:JAVA_HOME
Push-Location $backend
try{
    if($Build -or -not(Test-Path -LiteralPath $jar)){
        $env:JAVA_HOME=Split-Path (Split-Path $java -Parent) -Parent
        & (Join-Path $backend 'mvnw.cmd') --batch-mode --no-transfer-progress package
        if($LASTEXITCODE -ne 0){throw 'Build failed; server was not started.'}
    }
    $env:ECOCHECK_HOST=if($Lan){'0.0.0.0'}else{'127.0.0.1'}
    $env:ECOCHECK_PORT="$Port"
    if($Lan){
        Write-Host 'LAN access selected. Devices on the network may reach this server.'
        Write-Host 'Do not expose it to the public internet. This script does not change firewall rules.'
        Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway} |
            ForEach-Object {Write-Host ("Phone server URL: http://"+$_.IPv4Address.IPAddress+":$Port")}
    }else{Write-Host "Local server URL: http://127.0.0.1:$Port"}
    Write-Host 'Keep this terminal open. Stop with Ctrl+C. No external API is called merely by startup.'
    & $java -jar $jar
    if($LASTEXITCODE -ne 0){throw 'Server stopped with an error. Check the port and startup message.'}
}finally{
    $env:ECOCHECK_HOST=$previousHost
    $env:ECOCHECK_PORT=$previousPort
    $env:JAVA_HOME=$previousJavaHome
    Pop-Location
}
