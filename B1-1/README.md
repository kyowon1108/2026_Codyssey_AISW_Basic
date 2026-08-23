# B1-1 리눅스 서버 운영 환경 구축 및 시스템 관제 자동화

Ubuntu 22.04 LTS 환경에서 기본 보안(SSH, 방화벽), 역할 기반 권한 체계(계정, 그룹, ACL),
애플리케이션 실행 환경, 관제 자동화(monitor.sh + cron)를 구성한 결과물이다.

## 산출물

| 산출물 | 경로 |
|---|---|
| 요구사항 수행 내역서 | [`docs/수행내역서.md`](docs/수행내역서.md) |
| 자동화 스크립트 | [`scripts/monitor.sh`](scripts/monitor.sh) |
| 증거 자료 | [`docs/evidence/`](docs/evidence/) |

## 폴더 구조

```
B1-1/
├── agent-app/                  제공된 앱 바이너리 (arm64 / x86)
├── env/
│   ├── Dockerfile              Ubuntu 22.04 실습 환경 이미지
│   └── run.sh                  컨테이너 빌드 및 기동
├── setup/                      서버 구성 스크립트 (전부 Bash)
│   ├── 00_env.sh               공통 설정값, 헬퍼
│   ├── 01_ssh.sh               SSH 포트 20022, Root 원격 접속 차단
│   ├── 02_firewall.sh          UFW 활성화, 20022/15034 만 허용
│   ├── 03_users_groups.sh      계정 3개 / 그룹 2개 생성
│   ├── 04_dirs_acl.sh          디렉토리 구조 및 권한/ACL
│   ├── 05_app_env.sh           환경 변수, 키 파일, 앱 배치
│   ├── 06_run_app.sh           앱 기동/중지/상태 (start|stop|status)
│   ├── 07_monitor_deploy.sh    monitor.sh 배치 (agent-dev:agent-core 750)
│   ├── 08_cron.sh              agent-admin crontab 매분 등록
│   └── run_all.sh              01 ~ 08 일괄 실행
├── scripts/
│   └── monitor.sh              관제 자동화 스크립트
└── docs/
    ├── 수행내역서.md
    ├── 캡처가이드.md            제출용 화면 캡처 13컷 안내
    ├── capture_scenes.sh       캡처 화면을 한 컷씩 띄워주는 스크립트
    ├── collect_evidence.sh     증거 자료 수집
    ├── verify_ssh.sh           SSH 접속 검증
    ├── verify_failure_cases.sh 예외 동작 검증
    └── evidence/
        ├── *.txt               명령어 출력 원본
        └── img/                캡처 이미지
```

## 재현 방법

```bash
# 1) 실습 환경 기동 (호스트)
./env/run.sh

# 2) 서버 구성 일괄 수행 (컨테이너 내부, root)
docker exec agent-lab bash /mnt/B1-1/setup/run_all.sh

# 3) 증거 자료 수집 (호스트)
./docs/collect_evidence.sh

# 4) 검증 스크립트 (호스트, 선택)
./docs/verify_ssh.sh
./docs/verify_failure_cases.sh

# 5) 제출용 화면 캡처 (호스트)
./docs/capture_scenes.sh
```

캡처 절차는 [`docs/캡처가이드.md`](docs/캡처가이드.md)에 정리해 두었다.

`setup/*.sh`는 모두 멱등하게 작성되어 여러 번 실행해도 결과가 같다.

## 보너스 과제

`report.sh` 통계 리포트와 시간 기반 로그 압축/아카이브/삭제는 수행하지 않았다.
필수 요구사항인 10MB / 10개 파일 용량 기반 로그 관리는 `monitor.sh`에 구현되어 있다.
