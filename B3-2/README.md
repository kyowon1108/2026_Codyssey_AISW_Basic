# B3-2 — AI 커밋 메시지·PR 초안 생성기

Git 변경 사항을 수집하고 REST AI API에 전달해 변경 요약, 커밋 메시지 또는 PR 제목·본문을 터미널에 출력하는 Python CLI입니다. **실제 코디세이 API 호출과 로컬 통합 검증을 완료했습니다.** 자세한 요구사항별 증빙은 [검증 보고서](docs/verification.md)에 있습니다.

## 설치와 실행

Python 3.10 이상, Git, [uv](https://docs.astral.sh/uv/getting-started/installation/)가 필요합니다. 저장소 루트에서 설치합니다.

```bash
uv sync --project B3-2
export AI_API_KEY="발급받은_API_키"
B3-2/.venv/bin/python B3-2/main.py --help
B3-2/.venv/bin/python B3-2/main.py commit
B3-2/.venv/bin/python B3-2/main.py pr
```

`OPENAI_API_KEY`도 지원하며, 두 변수가 모두 설정되어 있으면 `AI_API_KEY`를 우선합니다. 키는 실행 프로세스의 환경변수에서만 읽습니다. 소스, 설정 파일, 로그에 키를 기록하지 않습니다. Windows PowerShell은 `$env:AI_API_KEY="발급받은_API_키"`, 실행 파일은 `B3-2/.venv/Scripts/python.exe`를 사용합니다.

반드시 **변경 내용을 설명할 Git 프로젝트의 루트**에서 실행하세요. 이 저장소의 `B3-2` 폴더 안에서 실행하면 루트 안내 오류가 발생합니다. 다른 저장소에서는 생성기의 절대 경로를 지정할 수 있습니다.

```bash
cd /path/to/target-repository
/path/to/2026_Codyssey_AISW_Basic/B3-2/.venv/bin/python \
  /path/to/2026_Codyssey_AISW_Basic/B3-2/main.py commit \
  --reason "입력 이름 앞뒤 공백 제거" \
  --requirements "타입 힌트와 공백 정리 동작 설명"
```

`uv run /absolute/path/to/B3-2/main.py commit`도 가능합니다. 실행 스크립트의 PEP 723 메타데이터로 의존성을 설치합니다. 재현성을 위해 제출 검증은 `uv.lock`을 사용하는 프로젝트 환경으로 실행했습니다.

## API와 옵션

기본 연결은 과제에서 제공한 **코디세이 API**입니다.

| 옵션 | 기본값·의미 |
|---|---|
| `commit` / `pr` | 생성할 초안 종류 |
| `--base-url` | `https://copa.codyssey.kr/v1`; 뒤에 `/chat/completions`를 붙여 POST |
| `--model` | `gpt-5-mini` |
| `--temperature` | 기본 생략: 모델 기본값 사용. 지정 시 0~2 |
| `--max-tokens` | 4000; 1~32768 범위. 요청의 `max_completion_tokens`에 연결 |
| `--reason` | 사용자에게 확인된 변경 이유; 최대 4000자 |
| `--requirements` | 관련 요구사항·검증 조건; 최대 4000자 |
| `--safe-mode` | 기본 활성화: 민감 파일 제외와 텍스트 마스킹 |
| `--raw-mode` | 파일 제외·마스킹 해제; 전송량 제한은 유지 |

```bash
B3-2/.venv/bin/python B3-2/main.py pr \
  --model gpt-5-mini --max-tokens 5000 \
  --reason "이름 입력 공백을 정리해 인사 문자열을 일관되게 표시" \
  --requirements "greet(' Alice ')가 Hello Alice를 반환"

# temperature를 지원하는 모델에만 직접 지정합니다.
B3-2/.venv/bin/python B3-2/main.py commit \
  --model YOUR_COMPATIBLE_MODEL --temperature 0.2

# OpenAI 공식 API를 사용하려면 해당 제공자 키와 주소를 함께 설정합니다.
B3-2/.venv/bin/python B3-2/main.py commit \
  --base-url https://api.openai.com/v1 --model gpt-4.1-mini --temperature 0.2
```

`temperature`가 낮으면 출력의 변동을 줄이고, 높으면 표현의 다양성을 높이는 방향으로 작동합니다. 모든 모델이 이 파라미터를 지원하지는 않으므로 기본은 생략합니다. `max_completion_tokens`는 출력 토큰 상한이며, 추론 모델에서는 추론 토큰도 포함합니다. 너무 작으면 내용이 잘릴 수 있습니다. 모델 이름·파라미터 지원 여부는 제공자별로 확인해야 합니다. [OpenAI 공식 API 문서](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create).

코디세이의 실제 검증에서는 `response_format`을 추가한 요청이 HTTP 400 `Requested feature is not supported.`로 거절됐습니다. 따라서 JSON 출력을 프롬프트로 요구하고 응답을 로컬에서 파싱·검증합니다. 실패 원인은 키나 전체 응답을 출력하지 않고 HTTP 상태와 마스킹한 오류 설명으로 안내합니다. HTTPS 외부 주소만 허용하며 HTTP는 로컬 테스트 서버에만 허용합니다.

## 수집·프롬프트·검증 흐름

1. `git rev-parse --show-toplevel`로 실행 위치를 확인하고 `git status --porcelain=v1 -z`로 변경 파일을 파악합니다.
2. 추적 파일의 일반 diff와 staged diff를 모두 수집합니다. 새 파일은 `git diff --no-index`로 수집하며, 파일 이름 변경은 원본·대상 경로를 함께 사용합니다. 외부 diff 프로그램·textconv는 실행하지 않습니다.
3. 민감정보를 제거하고 제한된 status/diff, 변경 이유, 요구사항을 JSON 컨텍스트로 구성합니다. Git 내용은 신뢰할 수 없는 자료로 취급하도록 지시하고, 확인하지 않은 테스트 성공이나 변경 이유를 만들어내지 않도록 지시합니다.
4. REST POST 요청 → 응답 구조 파싱 → 제목·본문 검증 → 터미널 출력 순서로 처리합니다. 제목은 한 줄이고 커밋 최대 72자, PR 최대 80자입니다. 커밋 제목 50자 초과는 검토 안내를 출력합니다. 커밋 본문을 생성했다면 핵심 변경 불릿이 있어야 합니다. PR에는 `## Why`, `## What`, `## How to Test`와 섹션마다 비어 있지 않은 불릿을 요구합니다.
5. 형식이 잘못되면 **한 번만 재생성**합니다. 두 번 실패하면 초안을 출력하지 않고 종료 코드 2를 반환합니다. 네트워크·인증·잘린 응답은 즉시 오류로 종료합니다. 정상·변경 없음은 종료 코드 0입니다.

변경이 없으면 API 키 없이도 `변경 사항이 없습니다. API 호출: 0회`로 종료합니다. 변경이 모두 민감 파일이면 전송 가능한 변경이 없다는 오류를 출력합니다. 정상 응답은 보통 1회, 형식 보정 시 최대 2회 호출합니다. HTTP 자동 재시도와 리다이렉트는 꺼서 요청 수와 키 전송 대상을 제한합니다.

도구는 **초안 출력까지** 수행합니다. 생성된 문구를 검토한 뒤 사용자가 복사해 커밋이나 PR 작성에 적용합니다. 도구 안에는 `git add`, `git commit`, `git push`, GitHub PR 생성 기능이 없습니다. 별도 검증 스크립트는 임시 저장소에서만 테스트용 초기 커밋을 만듭니다.

## 실제 출력 예시

2026-10-02에 임시 저장소의 `greeting.py`에 타입 힌트와 `name.strip()`을 추가한 뒤 코디세이 `gpt-5-mini`를 호출했습니다. 다음은 실제 결과의 제목과 본문 일부입니다. 생성 문구는 실행마다 달라질 수 있습니다.

```text
=== LIVE commit / exit=0 ===
[INFO] Git 변경 감지: 1개 파일, 제외: 0개
[DONE] 생성 및 형식 검증 완료 / API 호출: 1회

--- Change Summary ---
greet 함수에 타입 힌트 추가 및 입력 이름의 앞뒤 공백을 제거하도록 변경 (greeting.py 수정)

--- Commit Message ---
greet: 타입 힌트 추가 및 이름 공백 제거
- 변경 내용: greeting.py의 greet 함수 시그니처에 타입 힌트(name: str)와 반환 타입(-> str)을 추가하고, 반환 표현을 f-string으로 변경하여 name.strip()을 적용함.
```

```text
=== LIVE pr / exit=0 ===
[DONE] 생성 및 형식 검증 완료 / API 호출: 1회

--- PR Title ---
greet 함수 타입 힌트 추가 및 입력 공백 제거

--- PR Body ---
## Why
- 입력 이름의 앞뒤 공백 제거 (제공된 이유: "입력 이름의 앞뒤 공백 제거")와 코드에 타입 힌트를 명시해야 한다는 요구를 반영했습니다.

## What
- 대상 파일: greeting.py
- 변경 내용 요약:
  - 함수 시그니처를 def greet(name: str) -> str로 수정하여 매개변수와 반환에 타입 힌트 추가
  - 반환 구현을 문자열 연결에서 f-string으로 변경하고 name.strip()을 적용하여 입력 앞뒤 공백 제거 (return f"Hello {name.strip()}")

## How to Test
- from greeting import greet; assert greet(' Alice ') == 'Hello Alice'  # 앞뒤 공백이 제거되는지 확인
- assert greet('Bob') == 'Hello Bob'  # 기존 정상 입력 동작 확인
```

PR의 `How to Test`는 **제안된 테스트 방법**입니다. AI가 실제 실행했다는 증빙은 아닙니다. CLI 실행·형식 검증의 성공은 [검증 보고서](docs/verification.md)에 따로 기록했습니다.

## 안전 모드와 비용

- 전송 범위: 최대 **10개 파일, diff 200줄, diff 20,000자**. 제한이 걸리면 터미널과 컨텍스트에 표시합니다. 파일당 64KiB를 넘는 untracked 파일, 심볼릭 링크는 내용 대신 메타데이터만 전달합니다. 제한은 raw 모드에서도 유지됩니다.
- 기본 제외: `.env`, `.env.*`, `.aws/`, `.ssh/`, `.git/`, `.venv/`, `credentials`, `credentials.json`, `id_rsa`, `id_ed25519`, `.pem/.key/.p12/.pfx` 파일.
- 마스킹: `sk-` 키, AWS access key ID, GitHub 토큰, 이메일, PEM 개인키, `api_key/secret/password/token` 대입 패턴. diff를 **자르기 전에** 마스킹해 여러 줄 개인키의 일부가 잘려 전송되는 일을 줄입니다. 변경 이유·요구사항과 안전 모드의 생성 결과도 마스킹합니다.
- 정규식으로 모든 비밀정보를 탐지할 수는 없습니다. 코드와 파일명이 외부 API로 전송될 수 있으므로 민감한 저장소에서 사용하기 전에 전송 범위를 확인하세요. `--raw-mode`는 이러한 제거를 해제합니다.
- 생성 호출은 실행당 최대 2회이며, 별도 테스트 서버를 사용하는 자동 테스트에는 실 API 키나 비용이 필요 없습니다. 실 API 검증 스크립트는 commit/pr 각각 최대 2회, 합계 최대 4회 생성 요청을 할 수 있습니다.

## 검증 재현

```bash
cd B3-2
uv sync --locked
uv run pytest -q
uv run ruff check .
uv run ruff format --check .
uv run basedpyright
uv run --python 3.10 --isolated pytest -q

# 키가 설정된 경우에만 실제 API로 임시 저장소를 검증합니다.
uv run python -m scripts.verify_live
```

소스 구조: `gitgen/git.py`는 Git 수집, `safety.py`는 제외·마스킹, `api.py`는 REST 호출과 재생성, `models.py`는 입력·응답 모델과 형식 검증, `cli.py`는 옵션·출력을 담당합니다. `tests/`는 임시 Git 저장소와 실제 로컬 HTTP 서버로 CLI 흐름을 검증합니다.

GitHub 제출은 기존 과제 저장소의 B3-2 폴더를 사용합니다. 선택 보너스의 실제 PR 작성과 팀 컨벤션 커스터마이징은 이번 필수 과제 범위에 포함하지 않았습니다.
