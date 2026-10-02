# B3-1 재실습 리소스 정리 (2026-10-02)

서울 리전에서 `Project=codyssey-b3-1` 태그로 유형별 재조회했다. 원본은 [삭제 확인 출력](evidence/09-cleanup-cli.txt)에 보관했다.

- [x] EC2 `i-08b9ec3780da8b591`: `terminated` 확인 ([화면](evidence/08-ec2-terminated.jpg)).
- [x] EBS `vol-014a3dac45c625974`: 종료 후 볼륨 조회 `[]`.
- [x] VPC `vpc-01b4daf1733a7455c`, Subnet `subnet-0a138b26f5e4f612c`, IGW `igw-0b58684962d8619dd`, Route Table `rtb-025cfcc317a73b750`, SG `sg-05bbcc2ce0716bf89`: 각각 삭제 후 조회 `[]` ([VPC 화면](evidence/10-vpc-cleaned.jpg)).
- [x] EIP: 생성하지 않음. 임시 퍼블릭 IPv4는 EC2 종료 후 사라졌고 EIP 조회는 `[]`.
- [x] AWS 키페어와 IAM 역할 `codyssey-b3-1-evidence`: 삭제. IAM 재조회 `NoSuchEntity`, 로컬 개인 키 부재 확인.
- [x] NAT Gateway·ALB·RDS: 생성하지 않음. 기존 다른 프로젝트 리소스는 변경하지 않음.
- [ ] Billing 최종 청구: 반영 지연으로 이 시점에 확정하지 않았다.
