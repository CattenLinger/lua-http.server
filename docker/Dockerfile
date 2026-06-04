## Build dev environment
FROM debian:bookworm-slim AS lua52_dev_base
RUN DEBIAN_FRONTEND=no-interactive apt update \
    && apt install lua5.2 liblua5.2-dev luarocks \
           libssl-dev git build-essential m4 \
           ca-certificates \
           --no-install-recommends -y \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY .  /workspace

RUN luarocks install luafilesystem
RUN make all

FROM debian:bookworm-slim

RUN DEBIAN_FRONTEND=no-interactive apt update \
    && apt install libc6 lua5.2 ca-certificates \
           --no-install-recommends -y \
    && rm -rf /var/lib/apt/lists/*

COPY --from=lua52_dev_base \
    /workspace/docker/docker-entrypoint.sh \
    /workspace/build.make/runtime.tar.gz   \
    /workspace/build.make/app.tar.gz       \
    /

COPY --from=lua52_dev_base \
    /workspace/docker/docker-entrypoint.d  \
    /docker-entrypoint.d

RUN chmod +x /docker-entrypoint.sh && chmod -R +x /docker-entrypoint.d \
    && tar -xzvf /runtime.tar.gz -C / \
    && mkdir -p /opt/lhsvr && tar -xzvf /app.tar.gz -C /opt/lhsvr \
    && chmod -R +x /opt/lhsvr/bin \
    && ln -sf /opt/lhsvr/bin/http-server /usr/bin/http-server \
    && rm -rf /runtime.tar.gz /app.tar.gz \
    && chown -R www-data:www-data /srv

WORKDIR /srv
USER www-data

ENTRYPOINT ["/docker-entrypoint.sh"]
EXPOSE 80
CMD ["http-server", "-h", "0.0.0.0", "-p", "80"]