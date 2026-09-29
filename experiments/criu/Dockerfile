FROM debian:forky-slim@sha256:61c8340200f7d4e440dd0c52ac81628060da77410108afaebb23d38e43f39fa1

RUN apt-get update \
    && apt-get install -y --no-install-recommends criu=4.2.1-1 python3=3.14.7-3 \
    && rm -rf /var/lib/apt/lists/*

COPY supervisor.py workload.py /opt/criu-demo/
WORKDIR /opt/criu-demo
EXPOSE 8080
CMD ["python3", "supervisor.py"]
