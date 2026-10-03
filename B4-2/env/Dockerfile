FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive TZ=Asia/Seoul
RUN apt-get update && apt-get install -y --no-install-recommends \
    procps iproute2 tzdata ca-certificates \
    && rm -rf /var/lib/apt/lists/*
CMD ["bash"]
