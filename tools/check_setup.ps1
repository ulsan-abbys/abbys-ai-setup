param(
    [string]$Path = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$ok = $true

function Read-SetupFile {
    param([string]$Name)
    try {
        $file = Join-Path -Path $Path -ChildPath $Name
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            return ,@(Get-Content -LiteralPath $file -Encoding UTF8)
        }
    } catch {
        # 읽을 수 없는 파일도 점검 실패로 처리합니다.
    }
    return $null
}

$agents = Read-SetupFile 'AGENTS.md'
if ($null -ne $agents -and $agents.Count -le 150) {
    Write-Output "✓ AGENTS.md: 있음, $($agents.Count)줄 (150줄 이내)"
} else {
    Write-Output '✗ AGENTS.md: 파일이 없거나 읽을 수 없거나 150줄을 넘습니다.'
    $ok = $false
}

$claude = Read-SetupFile 'CLAUDE.md'
if ($null -ne $claude -and ($claude -join "`n").Contains('@AGENTS.md')) {
    Write-Output '✓ CLAUDE.md: @AGENTS.md 포함'
} else {
    Write-Output '✗ CLAUDE.md: 파일을 읽을 수 없거나 @AGENTS.md가 없습니다.'
    $ok = $false
}

$state = Read-SetupFile 'STATE.md'
if ($null -ne $state -and ($state -join "`n") -match '(?m)^updated:') {
    Write-Output '✓ STATE.md: updated: 포함'
} else {
    Write-Output '✗ STATE.md: 파일을 읽을 수 없거나 updated:가 없습니다.'
    $ok = $false
}

foreach ($tool in @('claude', 'codex')) {
    if (Get-Command -Name $tool -CommandType Application, ExternalScript -ErrorAction SilentlyContinue) {
        Write-Output "✓ ${tool}: PATH에서 찾았습니다."
    } else {
        Write-Output "✗ 안내: ${tool}를 PATH에서 찾지 못했습니다. README의 공식 설치 안내를 확인하세요. (실패 아님)"
    }
}

if ((Get-Command git -CommandType Application -ErrorAction SilentlyContinue) -and
    (Test-Path -LiteralPath $Path -PathType Container)) {
    $gitChecked = $false
    $tracked = @()
    try {
        $tracked = @(& git -C $Path ls-files --cached -- .env ':(glob)**/.env' 2>$null)
        $gitChecked = ($LASTEXITCODE -eq 0)
    } catch {
        # Git 저장소가 아니어도 세 파일의 점검 결과는 유지합니다.
    }
    if (-not $gitChecked) {
        Write-Output '✗ 안내: Git 추적 상태를 확인하지 못했습니다. .env를 추적하지 마세요. (실패 아님)'
    } elseif ($tracked.Count -gt 0) {
        Write-Output '✗ 안내: .env가 Git에 추적됩니다. 공유 전에 추적 상태를 확인하세요. (실패 아님)'
    } else {
        Write-Output '✓ 안내: 점검 폴더 아래 Git 추적 파일에 .env가 없습니다.'
    }
} else {
    Write-Output '✗ 안내: Git 추적 상태를 확인하지 못했습니다. .env를 추적하지 마세요. (실패 아님)'
}

if ($ok) {
    Write-Output '✓ 세 파일 점검 통과'
    exit 0
}
Write-Output '✗ 세 파일을 고친 뒤 다시 점검하세요.'
exit 1
