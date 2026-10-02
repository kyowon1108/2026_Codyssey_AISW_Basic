# B3-2 검증 보고서

검증일: 2026-10-02 (Asia/Seoul). 과제 기준: [Question.md](../Question.md).

## 검증 환경과 결과

- Python 3.12.12: `uv run pytest -q` → **41 passed**.
- Python 3.10: `uv run --python 3.10 --isolated pytest -q` → **41 passed**.
- `uv run ruff check .` → **All checks passed**.
- `uv run basedpyright` → **0 errors, 0 warnings, 0 notes**.
- `uv run ruff format --check .` → **모든 파일 포맷 통과**.
- omo Python 규칙 검사 → **no violations in 14 files**. 모듈별 책임을 분리했고 모든 소스 파일은 200 pure LOC 이하입니다.
- 실제 코디세이 `GET /v1/models` → **HTTP 200**, `gpt-5-mini` 사용 가능 확인.
- `scripts.verify_live`: 임시 Git 저장소에서 실제 `commit`, `pr` 호출 → **각 종료 코드 0, 각 API 1회**, 필수 형식 검증 성공, **Git 상태 불변 PASS**.

자동 테스트는 실 AI 모델의 품질 평가가 아니라 CLI·Git·HTTP·형식·보안 경계의 동작 검증입니다. 실제 AI 결과가 변경을 제대로 설명하는지는 아래 실 API 표본도 별도로 검토했습니다.

## 요구사항 대조

| 요구사항 | 구현·관찰 근거 | 판정 |
|---|---|---|
| 프로젝트 루트에서 status/diff 수집 | 루트 확인, NUL 구분 status, staged/unstaged/untracked diff | 충족 |
| 변경 없음 안내·종료 | 깨끗한 임시 저장소, 키 없이 종료 0, API 0회 | 충족 |
| API 키 환경변수 사용 | AI_API_KEY/OPENAI_API_KEY, 소스에 실제 키 없음 | 충족 |
| REST 요청·생성 결과 출력 | 실제 코디세이 API commit/pr 각각 성공 | 충족 |
| 오류 원인 안내 | 400/401/403/429/500/302 로컬 HTTP 서버, timeout/connect 오류 | 충족 |
| 모델·temperature·토큰 CLI 옵션 | 수신 HTTP JSON에서 옵션 값 확인, 범위 오류는 요청 0회 | 충족 |
| 커밋 제목 한 줄·본문 핵심 불릿 | 실제 출력 + 잘못된 제목 재생성 테스트 | 충족 |
| PR 제목·Why/What/How to Test 불릿 | 실제 출력 + 누락·빈 불릿 거부 테스트 | 충족 |
| 제목 길이 검증 | 커밋 72자/PR 80자 초과 거부, 잘못된 형식 최대 2회 | 충족 |
| 구분된 출력 | Change Summary, Commit Message 또는 PR Title/PR Body | 충족 |
| 안전 모드 | 기본 파일 제외·마스킹, 실제 HTTP 전송 본문에서 제거 확인 | 충족 |
| README 설치·실행·키·예시·주의사항 | [README.md](../README.md) | 충족 |
| GitHub 업로드 | 본 보고서가 포함된 제출 브랜치에서 소스 확인 | 제출 브랜치 기준 충족 |

제출 저장소: [kyowon1108/2026_Codyssey_AISW_Basic의 codex/b3-2 브랜치](https://github.com/kyowon1108/2026_Codyssey_AISW_Basic/tree/codex/b3-2/B3-2). 기존 저장소를 재사용하고 B3-2 구현·테스트·문서·의존성 잠금 파일만 업로드합니다. 다른 과제의 작업 파일은 제출 커밋에 포함하지 않습니다.

## 실 API 표본 검토

입력 변경은 `greeting.py`의 `greet(name)`에 `name: str`, `-> str` 타입 힌트를 추가하고, `"Hello " + name`을 `f"Hello {name.strip()}"`로 변경한 것입니다. 변경 이유는 입력 이름의 앞뒤 공백 제거, 요구사항은 타입 힌트와 공백 정리 동작을 설명하도록 제공했습니다.

- 커밋 제목: `greet: 타입 힌트 추가 및 이름 공백 제거`.
- PR 제목: `greet 함수 타입 힌트 추가 및 입력 공백 제거`.
- 두 결과 모두 실제 수정 파일·함수·타입 힌트·strip 변경을 설명했습니다.
- PR 필수 섹션과 비어 있지 않은 불릿을 포함했습니다.
- How to Test는 `greet(' Alice ')`, 정상 이름, 공백만 있는 이름, 타입 힌트 확인을 제안했습니다. 성공했다고 주장하지 않았습니다.
- 표본 검토 결과: 이 단일 변경에 대한 설명이 diff와 일치했습니다. 다른 모든 변경에서 같은 품질을 보장하는 결과는 아닙니다.

## 발견하고 해결한 문제

1. 이름 변경 시 대상 파일만 diff 경로로 전달하면 원본 삭제와 rename 정보가 빠졌습니다. 원본·대상 경로를 함께 보관·전달하도록 수정했고 rename 회귀 테스트가 통과했습니다.
2. 코디세이 API에 `response_format`을 추가하면 HTTP 400 `Requested feature is not supported.`가 발생했습니다. 옵션을 제거하고 프롬프트의 JSON 요청과 로컬 파싱·검증을 사용한 뒤 두 명령이 실제 성공했습니다.
3. 모델별 temperature 지원 차이를 고려해 기본 요청에서는 생략합니다. 사용자가 직접 지정하면 요청에 전달하고, 제공자 오류가 있으면 원인을 안내합니다.

## 재현 범위

테스트 항목에는 staged와 unstaged의 동시 변경, 새 파일의 공백·특수문자 이름, 삭제·rename, 루트 실행 제약, 키 누락, 민감 파일만 변경, 마스킹과 raw 모드 차이, 파일·줄·문자 제한, 정상 HTTP 요청, 인증·서버·리다이렉트 오류, 잘못된 응답 구조, 잘린 응답, 1회 형식 보정·2회 실패 종료, 잘못된 옵션, 네트워크 오류가 포함됩니다.

실 API 검증은 원본 과제 저장소의 미완성 변경을 보내지 않고, 별도의 임시 Git 저장소에서 수행했습니다. 도구 실행 전후의 status가 같았으며 테스트 서버 요청에는 실 키를 사용하지 않았습니다. 선택 보너스의 실제 PR 생성은 수행하지 않았습니다.
