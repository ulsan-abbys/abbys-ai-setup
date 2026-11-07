$ErrorActionPreference = 'Continue'
$env:PYTHONIOENCODING = 'utf-8'
$sbx = $PSScriptRoot
$script:results = New-Object 'System.Collections.Generic.List[object]'
$script:fatal = $false

function Save-Results {
    # Publish complete JSON files before exposing the completion marker.
    $temp = Join-Path $sbx 'results.tmp'
    ConvertTo-Json -InputObject @($script:results.ToArray()) -Depth 5 |
        Set-Content -LiteralPath $temp -Encoding UTF8 -ErrorAction Stop
    Move-Item -LiteralPath $temp -Destination (Join-Path $sbx 'results.json') -Force -ErrorAction Stop
}

function Invoke-Native {
    param([string]$Command, [string]$OutputFile)
    $capture = "$OutputFile.native"
    # PS 5.1 transcripts miss native output. cmd owns both redirections.
    & $env:ComSpec /d /c "$Command > ""$capture"" 2>&1"
    $code = $LASTEXITCODE
    if (Test-Path -LiteralPath $capture) {
        Get-Content -LiteralPath $capture -Raw -Encoding UTF8 |
            Add-Content -LiteralPath $OutputFile -Encoding UTF8
        Remove-Item -LiteralPath $capture -Force
    }
    return [int]$code
}

function Invoke-ChildPowerShell {
    param([string]$Code, [string]$OutputFile)
    $prefix = '$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); $OutputEncoding = [Console]::OutputEncoding; '
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($prefix + $Code))
    return (Invoke-Native "powershell -NoProfile -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand $encoded" $OutputFile)
}

function Step {
    param(
        [string]$Name, [bool]$Required, [int[]]$Expected,
        [string]$Slug, [scriptblock]$Action, [string]$MustContain = ''
    )
    $n = $script:results.Count + 1
    $output = Join-Path $sbx ('o_{0:00}_{1}.txt' -f $n, $Slug)
    Set-Content -LiteralPath $output -Value '' -Encoding UTF8
    Write-Host "[$n] $Name"
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $code = -1
    try {
        $code = & $Action $output
        if ($null -eq $code) { throw '단계 종료코드가 없습니다.' }
        $code = [int]$code
    } catch {
        $_ | Out-String | Add-Content -LiteralPath $output -Encoding UTF8
        $code = -1
    } finally {
        $ErrorActionPreference = 'Continue'
    }
    $content = [string](Get-Content -LiteralPath $output -Raw -Encoding UTF8)
    $containsOk = ($MustContain -eq '' -or $content.Contains($MustContain))
    $script:results.Add([pscustomobject]@{
        n = $n; name = $Name; required = $Required; exit = $code
        expected = @($Expected); contains_ok = $containsOk
        pass = ($Expected -contains $code -and $containsOk)
        seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 1)
    })
    Save-Results
    Write-Host $content
    Write-Host "exit=$code; expected=$($Expected -join ','); contains_ok=$containsOk"
}

try {
    Start-Transcript -Path (Join-Path $sbx 'transcript.txt') -Force -ErrorAction Stop | Out-Null
    Save-Results
    $config = Get-Content -LiteralPath (Join-Path $sbx 'config.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($config.source -notin @('github', 'local') -or [string]::IsNullOrWhiteSpace($config.branch)) {
        throw 'config.json의 source 또는 branch가 올바르지 않습니다.'
    }
    $root = Join-Path $HOME 'abbys'
    $frame = Join-Path $root 'abbys-content-frame'

    Step '환경' $false @(0) 'environment' {
        param($out)
        @([Environment]::OSVersion.VersionString, "PS $($PSVersionTable.PSVersion)",
            "winget: $([bool](Get-Command winget -ErrorAction SilentlyContinue))",
            "git: $([bool](Get-Command git -ErrorAction SilentlyContinue))") |
            Set-Content -LiteralPath $out -Encoding UTF8
        # Logon can start before DNS is ready; downloads then fail with 'could not be resolved'.
        $wait = [Diagnostics.Stopwatch]::StartNew()
        $ready = $false
        while (-not $ready -and $wait.Elapsed.TotalSeconds -lt 90) {
            try {
                foreach ($h in @('astral.sh', 'claude.ai', 'github.com')) { [void][Net.Dns]::GetHostEntry($h) }
                $ready = $true
            } catch { Start-Sleep -Seconds 2 }
        }
        "network_ready: $ready after $([Math]::Round($wait.Elapsed.TotalSeconds, 1))s" |
            Add-Content -LiteralPath $out -Encoding UTF8
        return 0
    }
    Step 'uv 설치' $true @(0) 'uv' {
        param($out)
        $code = Invoke-ChildPowerShell '$ErrorActionPreference = "Stop"; try { irm https://astral.sh/uv/install.ps1 | iex } catch { Write-Output $_; exit 1 }' $out
        $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
        $version = Invoke-Native 'uv --version' $out
        if ($code -ne 0) { return $code }
        return $version
    }
    Step 'Claude Code 설치' $true @(0) 'claude' {
        param($out)
        $code = Invoke-ChildPowerShell 'try { irm https://claude.ai/install.ps1 | iex; $ErrorActionPreference = "Continue" } catch { $ErrorActionPreference = "Continue"; Write-Output $_; exit 1 }' $out
        $ErrorActionPreference = 'Continue'
        $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
        $version = Invoke-Native 'claude --version' $out
        if ($code -ne 0) { return $code }
        return $version
    }
    Step '저장소 받기' $true @(0) 'repositories' {
        param($out)
        New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop | Out-Null
        foreach ($repo in @('abbys-ai-setup', 'abbys-content-frame')) {
            $dest = Join-Path $root $repo
            if ($config.source -eq 'local') {
                $src = "C:\Users\WDAGUtilityAccount\Desktop\src\$repo"
                $code = Invoke-Native "robocopy ""$src"" ""$dest"" /E /XD .git .venv logs __pycache__ .pytest_cache /XJ /R:1 /W:1" $out
                "robocopy $repo exit=$code (0..7 = 성공)" | Add-Content -LiteralPath $out -Encoding UTF8
                if ($code -ge 8) { return $code }
            } elseif (Get-Command git -ErrorAction SilentlyContinue) {
                # Encode PowerShell arguments rather than interpolate a branch into cmd syntax.
                $branchLiteral = ([string]$config.branch).Replace("'", "''")
                $destLiteral = $dest.Replace("'", "''")
                $code = Invoke-ChildPowerShell "& git clone --single-branch --branch '$branchLiteral' 'https://github.com/ulsan-abbys/$repo.git' '$destLiteral'; exit `$LASTEXITCODE" $out
                if ($code -ne 0) { return $code }
            } else {
                $branchUrl = [Uri]::EscapeDataString([string]$config.branch)
                $zip = Join-Path $root "$repo.zip"
                $extract = Join-Path $root "$repo-extract"
                Invoke-WebRequest "https://github.com/ulsan-abbys/$repo/archive/refs/heads/$branchUrl.zip" -OutFile $zip -UseBasicParsing -ErrorAction Stop
                Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force -ErrorAction Stop
                $folders = @(Get-ChildItem -LiteralPath $extract -Directory)
                if ($folders.Count -ne 1) { throw "ZIP 루트 폴더가 하나가 아닙니다: $repo" }
                Move-Item -LiteralPath $folders[0].FullName -Destination $dest -ErrorAction Stop
                "ZIP 다운로드: $repo ($($config.branch))" | Add-Content -LiteralPath $out -Encoding UTF8
            }
            if (-not (Test-Path -LiteralPath (Join-Path $dest 'README.md') -PathType Leaf)) {
                throw "README.md가 없습니다: $dest"
            }
        }
        return 0
    }
    Step 'frame graph' $true @(0) 'graph' {
        param($out)
        Set-Location -LiteralPath $frame -ErrorAction Stop
        Invoke-Native 'uv run frame graph' $out
    }
    Step 'frame check 예시 초안' $true @(1) 'example' {
        param($out)
        Set-Location -LiteralPath $frame -ErrorAction Stop
        Invoke-Native 'uv run frame check "examples\clinic\초안\01_겨울철-가려움-보습.md"' $out
    } '글자 수'
    Step 'frame check good fixture' $true @(0) 'good' {
        param($out)
        Set-Location -LiteralPath $frame -ErrorAction Stop
        Invoke-Native 'uv run frame check tests\fixtures\good.md' $out
    }
    Step 'frame check bad fixture' $true @(1) 'bad' {
        param($out)
        Set-Location -LiteralPath $frame -ErrorAction Stop
        Invoke-Native 'uv run frame check tests\fixtures\bad.md' $out
    } '[오류] medical.cure'
    Step 'pytest' $true @(0) 'pytest' {
        param($out)
        Set-Location -LiteralPath $frame -ErrorAction Stop
        Invoke-Native 'uv run --extra dev python -m pytest -q' $out
    } 'passed'
    Step 'check_setup' $true @(0) 'setup' {
        param($out)
        $setupLiteral = (Join-Path $root 'abbys-ai-setup\tools\check_setup.ps1').Replace("'", "''")
        $clinicLiteral = (Join-Path $frame 'examples\clinic').Replace("'", "''")
        Invoke-ChildPowerShell "& '$setupLiteral' -Path '$clinicLiteral'; exit `$LASTEXITCODE" $out
    }
} catch {
    $script:fatal = $true
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $sbx 'fatal.txt') -Encoding UTF8
} finally {
    $ErrorActionPreference = 'Continue'
    $passed = @($script:results | Where-Object { $_.required -and $_.pass }).Count
    $failed = @($script:results | Where-Object { $_.required -and -not $_.pass }).Count
    if ($script:fatal -or $script:results.Count -ne 10) { $failed++ }
    try { Save-Results } catch { $failed++ }
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    @{ finished_at = (Get-Date).ToString('o'); passed = $passed; failed = $failed } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sbx 'done.tmp') -Encoding UTF8
    Move-Item -LiteralPath (Join-Path $sbx 'done.tmp') -Destination (Join-Path $sbx 'done.json') -Force
}
