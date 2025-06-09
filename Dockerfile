ARG ALPINE_VERSION="3.12"

FROM alpine:${ALPINE_VERSION} AS PrivoxyBuilder
WORKDIR /tmp/privoxy

RUN echo "Build Privoxy" \
    && apk --no-cache add curl bash brotli-dev autoconf build-base libc-utils pkgconf lzip zlib-dev pcre-dev mbedtls-dev w3m \
    && addgroup -S privoxy && adduser -S privoxy -G privoxy \
    && curl -sL https://www.privoxy.org/sf-download-mirror/Sources/3.0.29%20%28stable%29/privoxy-3.0.29-stable-src.tar.gz | tar -C . --strip-components=2 -xz \
    && autoheader \
    && autoconf \
    && ./configure --enable-compression --with-brotli  --with-mbedtls --enable-extended-statistics  \
    && make -j4 \
    && make install-strip

FROM alpine:${ALPINE_VERSION} as TransmissionUIs

RUN apk --no-cache add curl jq wget \
    && mkdir -p /opt/transmission-ui \
    && echo "Install Shift" \
    && wget -qO- https://github.com/killemov/Shift/archive/master.tar.gz | tar xz -C /opt/transmission-ui \
    && mv /opt/transmission-ui/Shift-master /opt/transmission-ui/shift \
    && echo "Install Flood for Transmission" \
    && wget -qO- https://github.com/johman10/flood-for-transmission/releases/download/latest/flood-for-transmission.tar.gz | tar xz -C /opt/transmission-ui \
    && echo "Install Combustion" \
    && wget -qO- https://github.com/Secretmapper/combustion/archive/release.tar.gz | tar xz -C /opt/transmission-ui \
    && echo "Install kettu" \
    && wget -qO- https://github.com/endor/kettu/archive/master.tar.gz | tar xz -C /opt/transmission-ui \
    && mv /opt/transmission-ui/kettu-master /opt/transmission-ui/kettu \
    && echo "Install Transmission-Web-Control" \
    && mkdir /opt/transmission-ui/transmission-web-control \
    && curl -sL $(curl -s https://api.github.com/repos/ronggang/transmission-web-control/releases/latest | jq --raw-output '.tarball_url') | tar -C /opt/transmission-ui/transmission-web-control/ --strip-components=2 -xz \
    && echo "Install Transmissionic" \
    && wget -qO- https://github.com/6c65726f79/Transmissionic/releases/download/v1.8.0/Transmissionic-webui-v1.8.0.zip | unzip -q - \
    && mv web /opt/transmission-ui/transmissionic

FROM alpine:${ALPINE_VERSION} as base

RUN echo "@community http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories \
    && apk --no-cache add bash dumb-init ip6tables openvpn shadow transmission-daemon transmission-cli \
        wget curl jq tzdata openrc openssh unrar git pcre mbedtls \
    && apk --no-cache add --force-broken-world ufw@community \
    && mkdir -p /opt/transmission-ui \
    && ln -s /usr/share/transmission/web/style /opt/transmission-ui/transmission-web-control \
    && ln -s /usr/share/transmission/web/images /opt/transmission-ui/transmission-web-control \
    && ln -s /usr/share/transmission/web/javascript /opt/transmission-ui/transmission-web-control \
    && ln -s /usr/share/transmission/web/index.html /opt/transmission-ui/transmission-web-control/index.original.html \
    && rm -rf /tmp/* /var/tmp/* \
    && groupmod -g 1000 users \
    && useradd -u 911 -U -d /config -s /bin/false abc \
    && usermod -G users abc

FROM base

VOLUME /data
VOLUME /config

COPY --from=TransmissionUIs /opt/transmission-ui /opt/transmission-ui
COPY --from=PrivoxyBuilder /usr/local/etc/privoxy /usr/local/etc/privoxy
COPY --from=PrivoxyBuilder /usr/local/sbin/privoxy /usr/local/sbin/privoxy

# Add configuration and scripts
ADD openvpn/ /etc/openvpn/
ADD transmission/ /etc/transmission/
ADD scripts /etc/scripts/
ADD privoxy/scripts /opt/privoxy/

ENV OPENVPN_USERNAME=**None** \
    OPENVPN_PASSWORD=**None** \
    OPENVPN_PROVIDER=**None** \
    OPENVPN_OPTS= \
    GLOBAL_APPLY_PERMISSIONS=true \
    TRANSMISSION_HOME=/config/transmission-home \
    TRANSMISSION_RPC_PORT=9091 \
    TRANSMISSION_RPC_USERNAME= \
    TRANSMISSION_RPC_PASSWORD= \
    TRANSMISSION_DOWNLOAD_DIR=/data/completed \
    TRANSMISSION_INCOMPLETE_DIR=/data/incomplete \
    TRANSMISSION_WATCH_DIR=/data/watch \
    CREATE_TUN_DEVICE=true \
    ENABLE_UFW=false \
    UFW_ALLOW_GW_NET=false \
    UFW_EXTRA_PORTS= \
    UFW_DISABLE_IPTABLES_REJECT=false \
    PUID= \
    PGID= \
    PEER_DNS=true \
    PEER_DNS_PIN_ROUTES=true \
    DROP_DEFAULT_ROUTE= \
    WEBPROXY_ENABLED=false \
    WEBPROXY_PORT=8118 \
    WEBPROXY_USERNAME= \
    WEBPROXY_PASSWORD= \
    LOG_TO_STDOUT=false \
    HEALTH_CHECK_HOST=google.com \
    SELFHEAL=false

HEALTHCHECK --interval=1m CMD /etc/scripts/healthcheck.sh

# Pass revision as a build arg, set it as env var
ARG REVISION
ENV REVISION=${REVISION:-""}

# Compatability with https://hub.docker.com/r/willfarrell/autoheal/
LABEL autoheal=true

# Expose ports and run

#Transmission-RPC
EXPOSE 9091
# Privoxy
EXPOSE 8118

CMD ["dumb-init", "/etc/openvpn/start.sh"]
