FROM alpine:latest AS jsbuilder
ENV NODEJS_MAJOR=18
ENV DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.source="https://github.com/kmahyyg/ztncui-aio"
LABEL MAINTAINER="Key Networks https://key-networks.com"
LABEL Description="ztncui (a ZeroTier network controller user interface) + ZeroTier network controller"
ADD VERSION .

# BUILD ZTNCUI IN FIRST STAGE
WORKDIR /build
RUN apk update && \
    apk add curl gnupg ca-certificates zip unzip build-base git --no-cache && \
    apk add nodejs npm --no-cache && \
COPY build-ztncui.sh /build/
RUN sh /build/build-ztncui.sh

# BUILD GO UTILS
FROM golang:alpine AS gobuilder
WORKDIR /buildsrc
COPY argon2g /buildsrc/argon2g
COPY fileserv /buildsrc/fileserv
COPY ztnodeid /buildsrc/ztnodeid
COPY build-gobinaries.sh /buildsrc/build-gobinaries.sh
ENV CGO_ENABLED=0
RUN apk update && \
    apk add zip --no-cache && \
    sh /buildsrc/build-gobinaries.sh

# START RUNNER
FROM alpine:3.18 AS runner
ENV DEBIAN_FRONTEND=noninteractive
ENV AUTOGEN_PLANET=0
ARG OVERLAY_S6_ARCH
WORKDIR /tmp
RUN apk update && \
    apk add curl gnupg ca-certificates gzip xz iproute2 unzip net-tools procps --no-cache && \
    curl -L -O https://github.com/just-containers/s6-overlay/releases/download/v3.1.3.0/s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && rm /tmp/s6-overlay-noarch.tar.xz && \
    addgroup -g 2222 zerotier-one && \
    adduser -u 2222 -G zerotier-one -S zerotier-one && \
    addgroup root zerotier-one && \
    curl -sL -o zt-one.sh https://install.zerotier.com && \
    sh zt-one.sh && \
    rm -f zt-one.sh && \
    rm -rf /var/lib/zerotier-one && \
    rm -rf /var/cache/apk/*

WORKDIR /opt/key-networks/ztncui
COPY --from=jsbuilder /build/artifact.zip .
RUN unzip ./artifact.zip && \
    rm -f ./artifact.zip

WORKDIR /
COPY start_firsttime_init.sh /start_firsttime_init.sh
COPY start_zt1.sh /start_zt1.sh
COPY start_ztncui.sh /start_ztncui.sh

COPY --from=gobuilder /buildsrc/artifact-go.zip /tmp/
RUN unzip -d /usr/local/bin /tmp/artifact-go.zip && \
    rm -rf /tmp/artifact-go.zip && \
    chmod 0755 /usr/local/bin/* && \
    chmod 0755 /start_*.sh

COPY s6-rc.d/ /etc/s6-overlay/s6-rc.d/

EXPOSE 3000/tcp
EXPOSE 3180/tcp
EXPOSE 8000/tcp
EXPOSE 3443/tcp

VOLUME ["/opt/key-networks/ztncui/etc", "/etc/zt-mkworld", "/var/lib/zerotier-one"]
ENTRYPOINT [ "/init" ]
