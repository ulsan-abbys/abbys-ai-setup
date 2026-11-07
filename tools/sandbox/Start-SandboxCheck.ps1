[CmdletBinding()]
param(
    [ValidateSet('github', 'local')][string]$Source = 'github',
    [string]$LocalRoot = '',
    [string]$Branch = 'main',
    [string]$OutDir = (Join-Path $env:TEMP ('abbys-sbx\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [ValidateRange(1, 1440)][int]$TimeoutMin = 25,
    [ValidateRange(0, 65536)][int]$MemoryMB = 0,
    [switch]$NoNetwork,
    [string]$Label = '',
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$sandbox = Join-Path $env:WINDIR 'System32\WindowsSandbox.exe'
if (-not (Test-Path -LiteralPath $sandbox)) {
    Write-Host 'Windows Sandbox가 없습니다. Windows 11 Pro/Enterprise와 BIOS 가상화 설정을 확인하세요.'
    Write-Host '관리자 PowerShell에서 다음 명령을 실행하고 재부팅하세요:'
    Write-Host 'Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All'
    exit 2
}
if (Get-Process -Name WindowsSandbox, WindowsSandboxClient -ErrorAction SilentlyContinue) {
    Write-Host '샌드박스는 한 번에 하나만 실행할 수 있습니다. 기존 창을 닫고 다시 실행하세요.'
    exit 2
}

try {
    # PS 5.1 does not reliably populate PSScriptRoot in parameter defaults.
    if ([string]::IsNullOrWhiteSpace($LocalRoot)) {
        $LocalRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    }
    $OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
    # Never reuse old completion markers or overwrite another run's evidence.
    if ((Test-Path -LiteralPath $OutDir) -and
        @(Get-ChildItem -LiteralPath $OutDir -Force).Count -gt 0) {
        throw 'OutDir는 비어 있어야 합니다. 새 폴더를 지정하세요.'
    }
    if ($Source -eq 'local') {
        $LocalRoot = (Resolve-Path -LiteralPath $LocalRoot).ProviderPath
        foreach ($repo in @('abbys-ai-setup', 'abbys-content-frame')) {
            if (-not (Test-Path -LiteralPath (Join-Path $LocalRoot "$repo\README.md"))) {
                throw "LocalRoot에 $repo\README.md가 없습니다: $LocalRoot"
            }
        }
    }
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'guest.ps1') -Destination (Join-Path $OutDir 'guest.ps1')
    # Record the conditions with the evidence so each run explains itself.
    $hostOs = Get-CimInstance Win32_OperatingSystem
    @{ source = $Source; branch = $Branch; label = $Label; memory_mb = $MemoryMB
       networking = (-not $NoNetwork); started_at = (Get-Date).ToString('o')
       host_free_mb = [int]($hostOs.FreePhysicalMemory / 1KB) } | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $OutDir 'config.json') -Encoding UTF8

    $hostFolder = [System.Security.SecurityElement]::Escape($OutDir)
    $localMapping = ''
    if ($Source -eq 'local') {
        $escapedRoot = [System.Security.SecurityElement]::Escape($LocalRoot)
        $localMapping = @"
    <MappedFolder>
      <HostFolder>$escapedRoot</HostFolder>
      <SandboxFolder>C:\Users\WDAGUtilityAccount\Desktop\src</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
"@
    }
    $networking = if ($NoNetwork) { 'Disable' } else { 'Enable' }
    $memoryLine = if ($MemoryMB -gt 0) { "  <MemoryInMB>$MemoryMB</MemoryInMB>" } else { '' }
    $wsb = Join-Path $OutDir 'check.wsb'
    @"
<Configuration>
  <Networking>$networking</Networking>
$memoryLine
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$hostFolder</HostFolder>
      <SandboxFolder>C:\Users\WDAGUtilityAccount\Desktop\sbx</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
$localMapping
  </MappedFolders>
  <LogonCommand>
    <Command>powershell -ExecutionPolicy Bypass -File C:\Users\WDAGUtilityAccount\Desktop\sbx\guest.ps1</Command>
  </LogonCommand>
</Configuration>
"@ | Set-Content -LiteralPath $wsb -Encoding UTF8
    Write-Host "결과 폴더: $OutDir"
    if ($NoLaunch) {
        Write-Host "생성 완료 (실행 안 함): $wsb"
        exit 0
    }
    Start-Process -FilePath $sandbox -ArgumentList ('"{0}"' -f $wsb)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $nextMinute = 60
    $donePath = Join-Path $OutDir 'done.json'
    while (-not (Test-Path -LiteralPath $donePath)) {
        if ($timer.Elapsed.TotalMinutes -ge $TimeoutMin) {
            Write-Host "시간 초과. 부분 결과와 로그: $OutDir"
            Write-Host '샌드박스 창을 닫으세요. 샌드박스 내부 내용은 사라지고 결과 폴더는 남습니다.'
            exit 3
        }
        Start-Sleep -Seconds 5
        if ($timer.Elapsed.TotalSeconds -ge $nextMinute) {
            Write-Host ('경과: {0}분' -f [int][Math]::Floor($timer.Elapsed.TotalMinutes))
            $nextMinute += 60
        }
    }
    try {
        $done = Get-Content -LiteralPath $donePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $results = Get-Content -LiteralPath (Join-Path $OutDir 'results.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $results = @($results)
        $results | Select-Object @{n='단계';e={$_.name}},
            @{n='결과';e={if ($_.pass) {'PASS'} else {'FAIL'}}},
            @{n='종료코드';e={$_.exit}}, @{n='기대';e={$_.expected -join ','}},
            @{n='초';e={$_.seconds}} | Format-Table -AutoSize | Out-Host
        $required = @($results | Where-Object { $_.required -eq $true })
        $passed = ($results.Count -eq 10 -and $required.Count -eq 9 -and
            @($required | Where-Object { $_.pass -ne $true }).Count -eq 0 -and $done.failed -eq 0)
    } catch {
        Write-Host "결과를 읽지 못했습니다: $($_.Exception.Message)"
        $passed = $false
    }
    Write-Host "결과 폴더: $OutDir"
    Write-Host '샌드박스 창을 닫으세요. 샌드박스 내부 내용은 사라지고 결과 폴더는 남습니다.'
    if ($passed) { exit 0 }
    exit 1
} catch {
    Write-Host "준비 또는 실행 실패: $($_.Exception.Message)"
    Write-Host "결과 폴더: $OutDir"
    exit 2
}
