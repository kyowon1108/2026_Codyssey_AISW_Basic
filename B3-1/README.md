# B3-1 AWS 웹 배포

## 수행 내용

2026-10-02 서울 리전에 별도 VPC와 EC2를 구성해 B1-1 웹페이지를 배포함.
외부 접속과 SSH 검증을 마친 뒤 실습 리소스를 삭제함.

## 네트워크와 접근 제어

VPC `10.31.0.0/16`, 퍼블릭 서브넷 `10.31.1.0/24`, IGW와 기본 경로를 구성함.
HTTP 80은 공개하고 SSH 22는 개인 IP `/32`로 제한함.

[구조도](docs/architecture.png) · [VPC 화면](docs/evidence/01-vpc.jpg) · [라우트 화면](docs/evidence/02-route.jpg) · [SG 화면](docs/evidence/03-security-group.jpg)

## 서버와 SSH 검증

Amazon Linux 2023의 `t3.micro`에서 Nginx 실행과 내부 HTTP·아웃바운드 HTTPS의 200 응답을 확인함.
[SSH 원본 기록](docs/evidence/05-ssh-session.txt)에 원격 사용자·호스트와 서버의 `Accepted publickey` 항목을 남김.

[EC2 실행 화면](docs/evidence/04-ec2.jpg) · [IAM 역할 사용 기록](docs/evidence/00-iam-role.txt) · [적용 정책](docs/iam-policy.json)

## 외부 접속 검증

방식 A로 Chrome에서 `http://3.35.10.74/`의 페이지 표시를 확인함.
추가로 [외부 /health 응답](docs/evidence/07-external-health.txt)의 `200 OK`와 본문 `OK`를 확인함.

![외부 접속 화면](docs/web-browser.png)

## 정리와 한계

[체크리스트](docs/cleanup-checklist.md)에 EC2 종료와 잔여 리소스 삭제 확인을 기록했으며 당시 IP는 현재 접속되지 않음.
IAM은 작업·리전 범위로 제한했지만 리소스 태그 제한은 미적용이며 최종 청구 금액은 미확정임.

[트러블슈팅](docs/troubleshooting.md) · [EC2 종료 화면](docs/evidence/08-ec2-terminated.jpg) · [삭제 조회 원본](docs/evidence/09-cleanup-cli.txt) · [VPC 삭제 화면](docs/evidence/10-vpc-cleaned.jpg)
