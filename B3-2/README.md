# B3-2 AI 커밋 메시지·PR 초안 생성기

## 수행 내용

Git 변경 사항을 수집해 REST AI API로 변경 요약과 커밋·PR 초안을 생성하는 Python CLI를 구현함.
실제 코디세이 API 호출과 로컬 통합 검증을 수행함.

## 구현과 검증

변경 수집, 민감정보 마스킹, 응답 형식 검증과 오류 처리를 구현함.
[검증 보고서](docs/verification.md)에 테스트 41개 통과, 정적 검사와 실제 API 표본 검토 결과를 기록함.

## 실행 환경

| 항목 | 적용값 |
|---|---|
| 환경 | Python 3.10 이상, Git, uv임 |
| API 키 | `AI_API_KEY` 또는 `OPENAI_API_KEY`이며 전자를 우선함 |
| 기본 API | `https://copa.codyssey.kr/v1`임 |
| 기본 모델 | `gpt-5-mini`임 |
| 토큰 상한 | 기본 4000이며 `--max-tokens`로 지정함 |
| temperature | 기본 생략이며 지원 모델에서만 `--temperature`로 지정함 |

## 과제 필수 사용 예시

과제에서 요구한 설치·키 설정·생성 명령 예시임.
설치는 이 저장소 루트에서 수행하고 생성 명령은 변경을 설명할 Git 저장소 루트에서 수행하는 구조임.

```bash
uv sync --project B3-2
export AI_API_KEY="발급받은_API_키"
B3-2/.venv/bin/python B3-2/main.py commit
B3-2/.venv/bin/python B3-2/main.py pr --reason "이름 입력 공백 제거"
```

## 실제 커밋 출력

임시 저장소의 `greeting.py` 변경으로 실제 API를 호출했으며 제목과 핵심 변경이 일치함을 확인함.
다음은 생성 결과 발췌임.

```text
greet: 타입 힌트 추가 및 이름 공백 제거
- 변경 내용: greeting.py의 greet 함수 시그니처에 타입 힌트(name: str)와 반환 타입(-> str)을 추가하고, 반환 표현을 f-string으로 변경하여 name.strip()을 적용함.
```

## 실제 PR 출력

PR의 Why·What·How to Test 형식을 확인함.
아래는 실제 결과의 핵심 발췌이며 테스트 제안은 실행 성공 증빙과 구분함.

```markdown
greet 함수 타입 힌트 추가 및 입력 공백 제거

## Why
- 입력 이름의 앞뒤 공백 제거 (제공된 이유: "입력 이름의 앞뒤 공백 제거")와 코드에 타입 힌트를 명시해야 한다는 요구를 반영했습니다.

## What
- 대상 파일: greeting.py
- 변경 내용 요약:
  - 함수 시그니처를 def greet(name: str) -> str로 수정하여 매개변수와 반환에 타입 힌트 추가
  - 반환 구현을 문자열 연결에서 f-string으로 변경하고 name.strip()을 적용하여 입력 앞뒤 공백 제거 (return f"Hello {name.strip()}")

## How to Test
- from greeting import greet; assert greet(' Alice ') == 'Hello Alice'  # 앞뒤 공백이 제거되는지 확인
```

## 안전 모드와 한계

기본 안전 모드에서 민감 파일 제외와 키·개인정보 마스킹을 적용함.
도구는 초안만 출력하며 결과의 정확성은 사용자가 검토해야 하는 구조임.

| 항목 | 제한 |
|---|---|
| 전송 범위 | 최대 10개 파일·diff 200줄·20,000자임 |
| 생성 요청 | 정상 1회, 형식 보정 포함 최대 2회임 |
| 키 관리 | 환경변수에서만 읽으며 소스·로그에 기록하지 않음 |
| raw 모드 | 제외·마스킹을 해제하며 전송량 제한은 유지함 |

정규식 마스킹으로 모든 비밀정보를 탐지할 수는 없음.
Git 내용과 파일명이 외부 API로 전송되므로 민감한 저장소에서는 전송 범위 확인이 필요함.
