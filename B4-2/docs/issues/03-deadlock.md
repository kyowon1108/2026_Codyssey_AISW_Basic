# [Bug] Deadlock — 두 워커의 역순 자원 획득으로 순환 대기

## 1. Description (현상 설명)
2026-10-02 `MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=10`, `MULTI_THREAD_ENABLE=true`로 실행했다. 약 9초 후 두 워커의 로그가 `WAITING… BLOCKED`에서 멈췄고, 프로세스는 45초 관찰 종료까지 유지됐다.

## 2. Evidence & Logs (증거 자료)
- [마지막 앱 로그](../evidence/20261002T054757Z-69135/deadlock-before/application.log): Thread-1은 `Shared_Memory_A`, Thread-2는 `Socket_Pool_B`를 보유한다. 이어 Thread-1은 B, Thread-2는 A를 요청하고 둘 다 `BLOCKED`가 된다.
- [ps -fp / ps -L 출력](../evidence/20261002T054757Z-69135/deadlock-before/process.txt): 앱 PID 3157과 워커 TID가 유지되며 워커의 대기 지점은 `futex_wait_queue`다. PID 3121은 관제 대상 프로세스 트리의 PTY 런처다.
- [monitor.sh CSV](../evidence/20261002T054757Z-69135/deadlock-before/monitor.csv): 정체 구간에서 CPU 0.00%, RSS 합계 21,352KiB, 로그 2,727바이트가 유지됐다. [top -H](../evidence/20261002T054757Z-69135/deadlock-before/top-threads.txt)도 보관했다.

## 3. Root Cause Analysis (원인 분석)
관측 로그상 `Thread-1 → B → Thread-2 → A → Thread-1`의 순환 대기다. 독점 락(상호 배제), 보유한 채 추가 요청(점유 대기), 반환 전 강제 회수 없음(비선점), 반대 순서의 요청(순환 대기)이 교착상태의 네 조건에 대응한다.

PID 유지나 futex 대기만으로 교착을 확정하지 않고, 자원 보유·상대 자원 요청 로그와 진행 정체를 함께 근거로 사용했다. 바이너리 내부 락 구현은 분석하지 않았다.

## 4. Workaround & Verification (조치 및 검증)
`MULTI_THREAD_ENABLE`만 true → false로 변경했다. [변경 후 로그](../evidence/20261002T054757Z-69135/deadlock-after/application.log)에는 A/B/C의 `Task Completed`와 `All tasks completed`가 있고 이후 워커 로그도 진행한다.

| 항목 | Before: true | After: false |
|---|---|---|
| 워커 진행 | A/B 자원 대기로 정체 | 작업 완료, 후속 로그 진행 |
| 관찰 | 45초, PID 유지 | 45초, BLOCKED 없음 |

45초 뒤 런처/프로세스 그룹에 보낸 정리 신호는 장애 자체의 종료가 아니다. 단일 스레드는 임시 회피이며, 장기 해결에는 락 획득 순서를 통일하거나 제한 시간·반환 처리를 설계해야 한다. 변경 후 메모리 증가도 관측돼 서비스 전체 안정성을 보장하지 않는다.
