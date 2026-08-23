# 2026 Codyssey AI/SW Basic - B1-1 리눅스 실습 환경
# Ubuntu 22.04 LTS 기반. 과제 수행에 필요한 패키지만 설치하고,
# 실제 서버 설정(SSH/방화벽/계정/권한/cron)은 setup/*.sh 에서 수행한다.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Seoul

RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server \
        ufw \
        iptables \
        cron \
        acl \
        sudo \
        procps \
        iproute2 \
        tzdata \
        ca-certificates \
        vim-tiny \
        less \
        netcat-openbsd \
        sshpass \
    && rm -rf /var/lib/apt/lists/*

# 로그 타임스탬프를 KST 기준으로 남기기 위한 타임존 고정
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# sshd 구동에 필요한 런타임 디렉토리
RUN mkdir -p /var/run/sshd

# 컨테이너는 systemd 없이 유지. 서비스는 service ssh/cron start 로 기동한다.
CMD ["sleep", "infinity"]
