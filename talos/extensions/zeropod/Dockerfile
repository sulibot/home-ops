# syntax=docker/dockerfile:1
# Talos v1.14 amd64 bootstrap payload. This image is an init container, not a
# Talos system extension: it writes only to a hostPath mounted at /host.
FROM golang:1.26-bookworm@sha256:abe4f87f354c4f6d7ee3fb11b241c6b6c24a32ca50a2ebcc30493a2168e14048 AS launcher
WORKDIR /src
COPY shim-launcher.go .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o /shim-launcher ./shim-launcher.go

FROM ghcr.io/ctrox/zeropod-installer:v0.13.0@sha256:7fecc7abffdfa904a6f00cc8858103ca441b9653129e15effd49ca1e52b67b4b AS upstream-installer
FROM ghcr.io/ctrox/zeropod-criu:v4.2.1@sha256:8edbfb9749fb2aa5c212e609d1635b5f195d958ff579cde4cf535aa63004d521 AS upstream-criu

FROM debian:12-slim@sha256:f3034a6ec3c1205360777c4aae76234998866ad18806ae62b63a3f84ccad782b AS tar-builder
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends build-essential dpkg-dev xz-utils patch ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# Debian Bookworm 1.34+dfsg-1.2+deb12u1 includes CVE-2023-39804 and
# CVE-2022-48303 backports. Pin all three source package files independently;
# dpkg-source also validates the archive checksums in the .dsc file.
ADD --checksum=sha256:c092b25be17ab3b138aabb756497b038516a3f7d23604ccd4bf76ebbabff7a27 https://deb.debian.org/debian/pool/main/t/tar/tar_1.34%2Bdfsg-1.2%2Bdeb12u1.dsc /tmp/tar_1.34+dfsg-1.2+deb12u1.dsc
ADD --checksum=sha256:7d57029540cb928394defb3b377b3531237c947e795b51aa8acac0c5ba0e4844 https://deb.debian.org/debian/pool/main/t/tar/tar_1.34%2Bdfsg.orig.tar.xz /tmp/tar_1.34+dfsg.orig.tar.xz
ADD --checksum=sha256:e7cdc112e6810a0827b6081f6a4115eb630679a5f3d7cceffbc236d6b8d46d69 https://deb.debian.org/debian/pool/main/t/tar/tar_1.34%2Bdfsg-1.2%2Bdeb12u1.debian.tar.xz /tmp/tar_1.34+dfsg-1.2+deb12u1.debian.tar.xz
COPY tar-1.34-direct-gzip.patch /tmp/tar-1.34-direct-gzip.patch
RUN dpkg-source -x /tmp/tar_1.34+dfsg-1.2+deb12u1.dsc /tmp/tar-src \
    && cd /tmp/tar-src \
    && patch -p1 < /tmp/tar-1.34-direct-gzip.patch \
    && FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr --disable-nls \
    && make -j2 \
    && ./src/tar --version | grep 'tar (GNU tar) 1.34'

FROM debian:12-slim@sha256:f3034a6ec3c1205360777c4aae76234998866ad18806ae62b63a3f84ccad782b AS payload
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends patchelf gzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=launcher /shim-launcher /payload/bin/containerd-shim-zeropod-v2
COPY --from=upstream-installer /build/containerd-shim-zeropod-v2 /payload/bin/containerd-shim-zeropod-v2.real
COPY --from=upstream-installer /build/zeropod-netinfo /payload/bin/zeropod-netinfo
COPY --from=upstream-criu /bin/criu /payload/bin/criu
COPY --from=upstream-criu /lib/ /payload/lib/
COPY --from=tar-builder /tmp/tar-src/src/tar /payload/bin/tar
RUN cp /usr/bin/gzip /payload/bin/gzip \
    && LD_LIBRARY_PATH=/payload/lib ldd /payload/bin/criu /payload/bin/tar /payload/bin/gzip \
      | awk '/=> \// {print $3} /^[[:space:]]*\// {print $1}' \
      | sort -u \
      | while read -r library; do \
          if [ -f "$library" ] && [ "$library" != "/payload/lib/$(basename "$library")" ]; then \
            cp -L "$library" "/payload/lib/$(basename "$library")"; \
          fi; \
        done \
    && cp -L /lib64/ld-linux-x86-64.so.2 /payload/lib/ld-linux-x86-64.so.2 \
    && patchelf --set-interpreter /var/lib/zeropod/lib/ld-linux-x86-64.so.2 --force-rpath --set-rpath /var/lib/zeropod/lib /payload/bin/criu \
    && patchelf --set-interpreter /var/lib/zeropod/lib/ld-linux-x86-64.so.2 --force-rpath --set-rpath /var/lib/zeropod/lib /payload/bin/tar \
    && patchelf --set-interpreter /var/lib/zeropod/lib/ld-linux-x86-64.so.2 --force-rpath --set-rpath /var/lib/zeropod/lib /payload/bin/gzip
COPY criu-default.conf /payload/etc/criu-default.conf
COPY shim.json /payload/etc/shim.json

FROM alpine:3.21@sha256:3c81aa9a3d770b316568f4499e30461a5cd3fbd7180bd89e28e34894c7845832
COPY --from=payload /payload/ /payload/
COPY bootstrap.sh /bootstrap.sh
# The image itself uses musl. These smoke checks exercise the bundled glibc
# interpreter and dependency set at the same absolute path used on Talos.
RUN mkdir -p /var/lib/zeropod && cp -a /payload/. /var/lib/zeropod/ \
    && /var/lib/zeropod/bin/criu --version \
    && /var/lib/zeropod/bin/tar --version >/dev/null \
    && /var/lib/zeropod/bin/gzip --version >/dev/null \
    && printf 'compressed-tmpfs-check\n' >/tmp/zeropod-test.txt \
    && PATH=/var/lib/zeropod/bin /var/lib/zeropod/bin/tar -czf /tmp/zeropod-test.tar.gz -C /tmp zeropod-test.txt \
    && test "$(PATH=/var/lib/zeropod/bin /var/lib/zeropod/bin/tar -xOzf /tmp/zeropod-test.tar.gz zeropod-test.txt)" = compressed-tmpfs-check \
    && mkdir -p /tmp/shellless/var/lib/zeropod \
    && cp -a /payload/. /tmp/shellless/var/lib/zeropod/ \
    && test ! -e /tmp/shellless/bin/sh \
    && printf 'shellless-tmpfs-check\n' >/tmp/shellless/var/lib/zeropod/test.txt \
    && PATH=/var/lib/zeropod/bin /usr/sbin/chroot /tmp/shellless /var/lib/zeropod/bin/tar --create --gzip --file=/var/lib/zeropod/test.tar.gz --directory=/var/lib/zeropod test.txt \
    && test "$(PATH=/var/lib/zeropod/bin /usr/sbin/chroot /tmp/shellless /var/lib/zeropod/bin/tar --extract --gzip --to-stdout --file=/var/lib/zeropod/test.tar.gz test.txt)" = shellless-tmpfs-check \
    && test -x /var/lib/zeropod/bin/containerd-shim-zeropod-v2.real
ENTRYPOINT ["/bin/sh", "/bootstrap.sh"]
