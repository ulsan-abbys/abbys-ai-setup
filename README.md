# abbys-ai-setup

내 PC에 AI 일꾼 자리 만들기: Claude Code·codex 공통 로컬 세팅.

울산 애비스AI의 Windows 입문자를 위한 시작 파일입니다. 월 3만원 안팎의 Claude Pro 또는 ChatGPT Plus 구독을 쓰는 분을 대상으로 합니다. 짧은 규칙과 상태 기록으로 반복 설명을 줄입니다.

## 5분 세팅

PowerShell에서 진행합니다. `<내 폴더>`는 실제 프로젝트 경로로 바꾸세요.

(1) Git을 준비하고, 사용할 도구 하나를 공식 문서에 따라 설치합니다.

| 도구 | 설치 안내 |
|---|---|
| Claude Code | https://code.claude.com/docs |
| codex | https://developers.openai.com/codex |

(2) 저장소를 내려받습니다.

```powershell
git clone https://github.com/ulsan-abbys/abbys-ai-setup
Set-Location .\abbys-ai-setup
$setup = (Get-Location).Path
```

(3) 내 프로젝트 폴더에 세 파일을 복사합니다. 기존 파일이 있다면 내용을 먼저 확인하고 합치세요.

```powershell
$project = "$env:USERPROFILE\Documents\내프로젝트"
New-Item -ItemType Directory -Force -Path $project | Out-Null
Copy-Item -Path .\templates\AGENTS.md, .\templates\CLAUDE.md, .\templates\STATE.md -Destination $project -Confirm
```

`AGENTS.md`의 `○○`를 내 일에 맞게 채우세요. AI에게 인터뷰를 부탁해도 됩니다.

(4) 프로젝트 맨 위 폴더에서 실행합니다. 아래 두 명령 중 하나만 입력하세요.

```powershell
Set-Location $project
claude
# 또는 codex
```

첫 말: **STATE.md 읽고 시작해**

(5) AI 도구를 종료한 뒤 저장소 폴더로 돌아와 점검합니다.

```powershell
Set-Location $setup
powershell -ExecutionPolicy Bypass -File tools\check_setup.ps1 -Path $project
```

명령 형식: `powershell -ExecutionPolicy Bypass -File tools\check_setup.ps1 -Path <내 폴더>`
경로에 공백이 있으면 따옴표로 감싸세요. `<내 폴더>`를 그대로 입력하지 마세요.

## 목차

| 문서 | 내용 |
|---|---|
| [세 도구가 읽는 파일](guides/01_세_도구가_읽는_파일.md) | 공통 규칙과 Windows 주의점 |
| [토큰 아끼는 습관](guides/02_토큰_아끼는_습관.md) | 7가지 습관 |
| [서브에이전트 잘 쓰기](guides/03_서브에이전트_잘_쓰기.md) | 작은 위임과 확인 |
| [권장 설정](guides/04_권장_설정.md) | 선택해서 적용할 설정 |
| [30분 실습](practice/실습_30분.md) | 내 업무로 첫 작업 |
| [AI에게 맡기기](docs/AI에게_맡기기.md) | 복사해서 쓰는 요청문과 기여 방법 |

## AI에게 맡기기

사람이 모두 읽지 않아도 됩니다. AI에게 이 저장소 경로를 알려 주고 README와 guides를 읽게 하세요. [복사할 요청문](docs/AI에게_맡기기.md)으로 단계별 도움을 받을 수 있습니다.

## 하지 않는 것

- 비밀번호·API 키를 파일에 쓰지 않습니다.
- 자동 게시를 하지 않습니다. 결과는 사람이 확인합니다.

## 새 노트북에서 처음부터

아무것도 없는 윈도우 노트북이라면 [docs/새_노트북_세팅.md](docs/새_노트북_세팅.md)를 순서대로 따라 하세요 (15분). Git → Claude Code → uv → 저장소 받기 → 블로그 뼈대 돌려 보기.

## 표준으로 다이어트

붙여 본 기법을 공식 권장 구조로 다시 덜어 내는 법: [guides/05_표준으로_다이어트.md](guides/05_표준으로_다이어트.md)
