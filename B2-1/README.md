# B2-1 용돈 기입장

## 수행 내용

Python 표준 라이브러리로 거래·카테고리·예산을 관리하는 콘솔 프로그램을 구현함.
거래 추가·조회·검색·수정·삭제, 월 요약과 CSV 가져오기·내보내기를 지원함.

## 저장과 처리

| 항목 | 적용 내용 |
|---|---|
| 실행 환경 | Python 3.10 이상임 |
| 기본 저장 위치 | 실행 위치의 `./data`이며 `--data-dir`로 변경 가능함 |
| 거래 | `transactions.jsonl`에 저장함 |
| 카테고리 | `categories.jsonl`에 저장함 |
| 예산 | `budgets.jsonl`에 저장함 |

저장 시 전체 읽기·수정·쓰기 구간을 잠그고 임시 파일을 원본과 원자적으로 교체하도록 구현함.
목록·검색은 제너레이터로 읽으며 CSV 가져오기는 전체 검증 후 반영하도록 구현함.

## 검증 범위

재실행 후 데이터 유지, 예산 사용률·초과 표시, 사용 중인 카테고리 삭제 거부와 저장 파일 보호를 검증함.
입력·파일 오류는 원인과 해결 힌트를 출력하고 0이 아닌 종료 코드를 반환하도록 구현함.

## 과제 필수 명령 예시

아래는 과제에서 요구한 사용 예시이며, 명령의 실행 위치는 `B2-1`임.
`add`는 대화형 입력을 사용하고 `update`는 옵션 입력을 사용함.

```bash
python -m budget_app --help
python -m budget_app add
python -m budget_app list --limit 20
python -m budget_app search --category food --q 점심
python -m budget_app summary --month 2024-01
python -m budget_app category add --name food
python -m budget_app category list
python -m budget_app category remove --name food
python -m budget_app budget set --month 2024-01 --amount 500000
python -m budget_app update --id TX-... --amount 18000
python -m budget_app delete --id TX-...
python -m budget_app import --from incoming.csv
python -m budget_app export --out january.csv --month 2024-01
```

## CSV 형식

UTF-8과 헤더를 사용하며 내보내기 열 순서는 `date,type,category,amount,memo,tags`임.
기존 CSV 교체는 `--force`로 명시해야 하며 내부 저장 파일은 덮어쓸 수 없음.

| 열 | 필수 | 형식 |
|---|---|---|
| `date` | 예 | `YYYY-MM-DD`임 |
| `type` | 예 | `income` 또는 `expense`임 |
| `category` | 예 | 등록된 카테고리임 |
| `amount` | 예 | 양의 정수임 |
| `memo` | 아니요 | 자유 텍스트임 |
| `tags` | 아니요 | 쉼표로 구분하며 CSV에서는 `"meal,work"`처럼 인용함 |
