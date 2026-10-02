# B3-1 리소스 정리 (2026-10-02)

서울 리전에서 `Project=codyssey-b3-1` 태그와 리소스 ID로 재조회했다.

- [x] EC2 `i-0d519f1c43568916c`: `terminated` 확인.
- [x] EBS `vol-084c8d7edae3002a8`: 인스턴스 종료 후 태그 조회 결과 `[]`.
- [x] VPC `vpc-02108e05a5fa5f02e`, Subnet `subnet-0542b334698bfc0b8`, IGW `igw-09361aedeb6ffce36`, Route Table `rtb-00bc7e9df408462a3`, SG `sg-0a09807d836a10201`: 삭제 후 유형별 태그 조회 모두 `[]`.
- [x] 실습 EIP: 미생성; 임시 퍼블릭 IPv4는 EC2 종료와 함께 해제. EIP 태그 조회 `[]`.
- [x] AWS 키페어와 전용 IAM 역할 `codyssey-b3-1-lab`: 삭제. IAM 조회는 `NoSuchEntity`, 로컬 개인 키도 제거.
- [x] NAT Gateway·ALB·RDS: 미생성. 기존 `wolgyeham` EC2는 계속 `running`인 것을 확인.
- [ ] Billing 최종 청구: 사용량 반영 지연이 있어 이 시점에 확정하지 않았다.

조회 예: `aws ec2 describe-vpcs --region ap-northeast-2 --filters Name=tag:Project,Values=codyssey-b3-1`. 종료된 EC2 기록은 잠시 조회될 수 있으므로 `State=terminated`를 확인했다.
