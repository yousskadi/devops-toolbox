FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl git vim jq wget unzip ca-certificates \
    iproute2 dnsutils net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# kubectl (base)
RUN curl -LO https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

WORKDIR /workspace

COPY .devcontainer .devcontainer

RUN chmod +x .devcontainer/scripts/*.sh .devcontainer/features/*.sh