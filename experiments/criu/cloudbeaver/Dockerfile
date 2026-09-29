FROM ghcr.io/ctrox/zeropod-criu:v4.2.1@sha256:724546f6469be658573fc29a0988eaa51cbd969ecc3d5d5bd6d4847cc23dddfd AS criu

FROM docker.io/dbeaver/cloudbeaver:26.1.1@sha256:9e5fbd45cae0e8715106a64d82efeac99ed070e8461ffca00bab1bf5ac7504ad

# The pinned CRIU 4.2.1 artifact is built against an older glibc than Ubuntu 24.04.
# Keep its support libraries private to CRIU rather than altering the JVM's loader path.
COPY --from=criu /bin/criu /usr/local/bin/criu
COPY --from=criu /lib/ /opt/criu-libs/

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/* \
    && LD_LIBRARY_PATH=/opt/criu-libs /usr/local/bin/criu --version

COPY supervisor.py /opt/criu-cloudbeaver/supervisor.py
WORKDIR /opt/cloudbeaver
EXPOSE 8080 8082
ENTRYPOINT ["python3", "/opt/criu-cloudbeaver/supervisor.py"]
