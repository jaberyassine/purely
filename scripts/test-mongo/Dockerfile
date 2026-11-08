# Disposable integration fixture only. The runtime calls mongod directly as 999.
FROM mongo:8.0.34
USER root
RUN set -eux; \
    apt-get update; \
    apt-mark manual mongodb-org-server mongodb-mongosh; \
    apt-get install -y --no-install-recommends --only-upgrade apt libapt-pkg6.0t64; \
    apt-get purge -y mongodb-org mongodb-org-database mongodb-org-tools \
        mongodb-org-database-tools-extra mongodb-database-tools mongodb-org-mongos; \
    rm -rf /opt/js-yaml /js-yaml.js /usr/local/bin/gosu \
        /usr/local/bin/docker-entrypoint.sh /var/lib/apt/lists/*; \
    test -x /usr/bin/mongod; \
    test -x /usr/bin/mongosh; \
    test ! -e /usr/local/bin/gosu; \
    test ! -e /opt/js-yaml; \
    test ! -e /js-yaml.js; \
    ! command -v mongodump; \
    ! command -v mongoimport; \
    mongod --version; \
    HOME=/tmp/mongo-build-probe mongosh --version; \
    rm -rf /tmp/mongo-build-probe
USER 999:999
ENTRYPOINT ["mongod"]
CMD ["--auth", "--bind_ip_all", "--wiredTigerCacheSizeGB", "0.25"]
