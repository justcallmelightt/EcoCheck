param([string]$BaseUrl='http://127.0.0.1:8080')
$ErrorActionPreference='Stop'
$uri=[uri]$BaseUrl
if($uri.Scheme -notin @('http','https') -or $uri.UserInfo -or $uri.Query -or $uri.Fragment){throw 'Use a base server URL without credentials, query or fragment.'}
$BaseUrl=$BaseUrl.TrimEnd('/')
$token=[guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N')
$cases=@(
    @{Name='Database health';Path='/health';Status=200;Auth=$false;Test={param($j)$j.database -eq 'ready'}},
    @{Name='Recycling guides';Path='/api/v1/categories';Status=200;Auth=$false;Test={param($j)$j.Count -eq 5}},
    @{Name='Nearby bins contract';Path='/api/v1/bins?lat=37.5665&lng=126.978&radius=1000&type=all';Status=200;Auth=$false;Test={param($j)$null -ne $j.items -and $j.count -eq $j.items.Count}},
    @{Name='Fresh device history';Path='/api/v1/scans?limit=50&offset=0';Status=200;Auth=$true;Test={param($j)$j.total -eq 0}},
    @{Name='Fresh device statistics';Path='/api/v1/statistics';Status=200;Auth=$true;Test={param($j)$j.totalScans -eq 0}},
    @{Name='Missing token rejected';Path='/api/v1/scans';Status=401;Auth=$false;Test={param($j)$j.error.code -eq 'UNAUTHORIZED'}},
    @{Name='Invalid location rejected';Path='/api/v1/bins?lat=NaN&lng=127';Status=400;Auth=$false;Test={param($j)$j.error.code -eq 'INVALID_LOCATION'}},
    @{Name='Invalid page rejected';Path='/api/v1/scans?limit=101';Status=400;Auth=$true;Test={param($j)$j.error.code -eq 'INVALID_QUERY'}},
    @{Name='Unknown path rejected';Path='/api/v1/not-existing';Status=404;Auth=$false;Test={param($j)$j.error.code -eq 'NOT_FOUND'}}
)
$passed=0
foreach($case in $cases){
    $headers=@{}
    if($case.Auth){$headers.Authorization="Bearer $token"}
    $status=0;$body=''
    try{
        $response=Invoke-WebRequest -Uri ($BaseUrl+$case.Path) -Headers $headers -TimeoutSec 15 -UseBasicParsing
        $status=[int]$response.StatusCode;$body=$response.Content
    }catch{
        $response=$_.Exception.Response
        if(-not $response){throw "Cannot reach $BaseUrl. Start the server first."}
        $status=[int]$response.StatusCode
        if($_.ErrorDetails -and $_.ErrorDetails.Message){$body=$_.ErrorDetails.Message}
        elseif($response -is [System.Net.Http.HttpResponseMessage]){$body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()}
        else{
            $reader=New-Object IO.StreamReader($response.GetResponseStream())
            try{$body=$reader.ReadToEnd()}finally{$reader.Dispose()}
        }
    }
    $json=$body|ConvertFrom-Json
    if($status -ne $case.Status -or -not(& $case.Test $json)){throw "FAIL: $($case.Name), HTTP $status"}
    Write-Host "PASS: $($case.Name) (HTTP $status)"
    $passed++
}
Write-Host "Passed $passed/$($cases.Count). Read-only checks; no external AI or map request was sent."
