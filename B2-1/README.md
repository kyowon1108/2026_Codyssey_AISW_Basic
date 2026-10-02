# B2-1 용돈 기입장

Python 표준 라이브러리만 사용하는 콘솔 가계부입니다. 거래·카테고리·예산을 JSONL 파일 3개에 영구 저장합니다.

## 실행

Python 3.10 이상에서 저장소 루트의 `B2-1` 폴더로 이동합니다.

```bash
cd B2-1
python -m budget_app --help
python -m budget_app add
```

기본 저장 폴더는 현재 작업 폴더의 `./data`입니다. 다른 위치를 사용하려면 **명령어 앞에** `--data-dir`을 지정합니다.

```bash
python -m budget_app --data-dir /tmp/my-budget list --limit 10
```

모든 명령과 하위 명령에서 `--help`를 사용할 수 있습니다. `add`는 날짜·타입·카테고리·금액·메모·태그를 순서대로 묻습니다. `category add/remove`도 `--name`을 생략하면 대화형으로 입력받습니다. `update`는 **옵션 방식만** 사용합니다.

## 주요 명령

```bash
python -m budget_app add
python -m budget_app list --limit 20
python -m budget_app search --from 2024-01-01 --to 2024-01-31 --category food --type expense --q 점심 --tag meal
python -m budget_app summary --month 2024-01 --top 3
python -m budget_app budget set --month 2024-01 --amount 500000
python -m budget_app budget show --month 2024-01
python -m budget_app category add
python -m budget_app category list
python -m budget_app category remove --name food
python -m budget_app update --id TX-... --amount 18000 --memo 저녁 --tags meal,friends
python -m budget_app delete --id TX-...
python -m budget_app import --from incoming.csv
python -m budget_app export --out january.csv --month 2024-01
python -m budget_app export --out range.csv --from 2024-01-01 --to 2024-01-31
python -m budget_app export --out range.csv --month 2024-01 --force
```

`list`와 `search`는 **거래 날짜가 최신인 순서**로 보여줍니다. `--limit` 기본값은 20입니다. `search` 조건은 함께 사용할 수 있습니다. `export`는 `--month` 또는 `--from`/`--to` 날짜 조건을 하나 이상 요구합니다. 예산 사용률은 월 지출 ÷ 월 예산이며, 초과 시 경고합니다.

`export`는 기존 파일을 기본적으로 덮어쓰지 않습니다. 기존 CSV를 교체할 때만 `--force`를 사용하며, 거래·카테고리·예산 JSONL 파일과 `.ledger.lock`은 `--force`로도 덮어쓸 수 없습니다.

처음 실행하면 `food`, `transport`, `rent`, `salary`, `other` 카테고리가 만들어집니다. 카테고리가 등록되지 않은 거래는 추가하거나 가져올 수 없습니다. 사용 중인 카테고리는 삭제할 수 없습니다. 카테고리를 모두 삭제했다면 `category add`로 다시 등록해야 합니다.

## 저장 위치와 형식

기본 저장 위치는 `B2-1/data/`이며, `--data-dir`로 변경할 수 있습니다.

| 파일 | JSONL 한 줄의 예 |
| --- | --- |
| `transactions.jsonl` | `{"id":"TX-...","type":"expense","date":"2024-01-15","amount":15000,"category":"food","memo":"점심","tags":["meal"]}` |
| `categories.jsonl` | `{"name":"food"}` |
| `budgets.jsonl` | `{"month":"2024-01","amount":500000}` |

같은 폴더에 `.ledger.lock` 파일도 생깁니다. 이 파일은 기록 데이터가 아니라 여러 CLI 프로세스의 동시 저장을 조정하는 잠금 파일입니다.

거래 추가·수정·삭제와 일괄 가져오기는 잠금을 잡은 상태에서 임시 파일을 완성한 뒤 원본과 원자적으로 교체합니다. 저장된 거래 파일은 날짜순으로 유지하며, 목록과 검색은 파일을 통째로 메모리에 올리지 않고 `yield` 제너레이터로 읽습니다. 가져오기는 CSV 전체를 먼저 검증하므로 잘못된 행이 있으면 **아무 거래도 반영하지 않습니다**.

## CSV 스키마

UTF-8, 첫 줄 헤더 포함입니다. 내보내기는 아래 6개 열을 항상 씁니다. 가져오기는 앞의 필수 4개 열이 필요하며 `memo`, `tags`는 생략할 수 있습니다.

| 열 | 필수 | 값 |
| --- | --- | --- |
| `date` | 예 | `YYYY-MM-DD` |
| `type` | 예 | `income` 또는 `expense` |
| `category` | 예 | 등록된 카테고리 |
| `amount` | 예 | 0보다 큰 정수 |
| `memo` | 아니요 | 자유 텍스트 |
| `tags` | 아니요 | `meal,work`처럼 쉼표로 구분. CSV 안에서는 `"meal,work"`처럼 인용 |

오류는 원인과 해결 힌트를 출력하고 0이 아닌 코드로 종료합니다. 정상 명령은 0으로 종료합니다.

## 구조와 검증

- `models.py`: `Transaction` 데이터 모델과 수정 값
- `storage.py`: 3개 JSONL 파일, 제너레이터 조회, 원자적 교체
- `service.py`: 카테고리·거래·예산 규칙, 검색과 월 요약
- `csv_io.py`: CSV 가져오기/내보내기
- `cli.py`, `commands.py`: 명령 파싱과 대화형 입력·출력. `handle_cli_errors` 데코레이터가 공통 오류 출력을 맡음

```bash
python -m unittest discover -s tests -v
```
