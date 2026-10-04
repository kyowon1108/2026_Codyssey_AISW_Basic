# B3-2 검증 보고서

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
| 토큰 설정별 실제 출력 비교 | 같은 모델·diff에서 2000/4000으로 각각 commit/pr 실행, PR 본문 525/798자 | 관측 완료; 고정 길이 보장 아님 |
| 커밋 제목 한 줄·본문 핵심 불릿 | 실제 출력 + 잘못된 제목 재생성 테스트 | 충족 |
| PR 제목·Why/What/How to Test 불릿 | 실제 출력 + 누락·빈 불릿 거부 테스트 | 충족 |
| 제목 길이 검증 | 커밋 72자/PR 80자 초과 거부, 잘못된 형식 최대 2회 | 충족 |
| 구분된 출력 | Change Summary, Commit Message 또는 PR Title/PR Body | 충족 |
| 안전 모드 | 기본 파일 제외·마스킹, 실제 HTTP 전송 본문에서 제거 확인 | 충족 |
| README 설치·실행·키·예시·주의사항 | [README.md](../README.md) | 충족 |
| GitHub 업로드 | 본 보고서가 포함된 제출 브랜치에서 소스 확인 | 제출 브랜치 기준 충족 |

제출 저장소: [kyowon1108/2026_Codyssey_AISW_Basic의 test/b3-2 브랜치](https://github.com/kyowon1108/2026_Codyssey_AISW_Basic/tree/test/b3-2/B3-2).

## 실 API 표본 검토

입력 변경은 `greeting.py`의 `greet(name)`에 `name: str`, `-> str` 타입 힌트를 추가하고, `"Hello " + name`을 `f"Hello {name.strip()}"`로 변경한 것입니다. 변경 이유는 입력 이름의 앞뒤 공백 제거, 요구사항은 타입 힌트와 공백 정리 동작을 설명하도록 제공했습니다.

- 커밋 제목: `greet: 타입 힌트 추가 및 이름 공백 제거`.
- PR 제목: `greet 함수 타입 힌트 추가 및 입력 공백 제거`.
- 두 결과 모두 실제 수정 파일·함수·타입 힌트·strip 변경을 설명했습니다.
- PR 필수 섹션과 비어 있지 않은 불릿을 포함했습니다.
- How to Test는 `greet(' Alice ')`, 정상 이름, 공백만 있는 이름, 타입 힌트 확인을 제안했습니다.
- 표본 검토 결과: 이 단일 변경에 대한 설명이 diff와 일치했습니다.

## 발견하고 해결한 문제

1. 이름 변경 시 대상 파일만 diff 경로로 전달하면 원본 삭제와 rename 정보가 빠졌습니다. 원본·대상 경로를 함께 보관·전달하도록 수정했고 rename 회귀 테스트가 통과했습니다.
2. 코디세이 API에 `response_format`을 추가하면 HTTP 400 `Requested feature is not supported.`가 발생했습니다. 옵션을 제거하고 프롬프트의 JSON 요청과 로컬 파싱·검증을 사용한 뒤 두 명령이 실제 성공했습니다.
3. 모델별 temperature 지원 차이를 고려해 기본 요청에서는 생략합니다. 사용자가 직접 지정하면 요청에 전달하고, 제공자 오류가 있으면 원인을 안내합니다.

## 2026-10-04 재확인

자동 테스트 41개와 실제 CLI의 변경 없음·키 누락 응답을 다시 확인하고 [현재 실행 로그](evidence/cli-boundaries.txt)와 [테스트 로그](evidence/tests.txt)를 보존함.
Carbon 이미지는 2026-10-02 실 API 발췌와 2026-10-04 CLI 출력을 구분해 제작함.

## 2026-10-04 실 API 비교와 재검토

Question.md 필수 요구사항과 평가 항목을 재대조하고, 같은 `greeting.py` 변경·이유·요구사항·`gpt-5-mini` 모델로 토큰 상한만 변경해 실행함.
각 명령의 원본 출력·종료 코드·API 호출 횟수·Git 상태 불변 결과를 보존함.

| 조건 | 커밋 제목/본문 글자 수 | PR 제목/본문 글자 수 | 실행 결과 |
|---|---|---|---|
| [2000 토큰](evidence/live-20261004-2000.txt) | 23 / 219 | 19 / 525 | 두 명령 모두 종료 0·API 1회·Git 불변임 |
| [4000 토큰](evidence/live-20261004-4000.txt) | 26 / 204 | 29 / 798 | 두 명령 모두 종료 0·API 1회·Git 불변임 |

두 PR 모두 필수 헤더·불릿과 길이 규칙을 만족하며 테스트 방법은 제안으로 출력됨.
이 표는 실제 문구 차이의 관측이며 반복 실행의 동일 문구, 토큰 사용량 또는 상한 증가에 따른 길이 증가를 보장하는 근거는 아님.

자동 테스트 41개와 ruff 검사·포맷·basedpyright를 재실행해 통과함.
GitHub 제출 PR 본문은 수동 수정한 것으로, AI 도구 생성 로그 및 선택 보너스의 AI 초안 적용 PR과 구분함.
