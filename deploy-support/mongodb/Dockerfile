# Standalone demo database server. Persistent data and TLS are configured by Kubernetes.
FROM mongo:8.0.34
USER root
RUN set -eux; \
    apt-get update; \
    apt-mark manual mongodb-org-server mongodb-mongosh; \
    apt-get upgrade -y; \
    apt-get purge -y mongodb-org mongodb-org-database mongodb-org-tools \
        mongodb-org-database-tools-extra mongodb-database-tools mongodb-org-mongos; \
    rm -rf /opt/js-yaml /js-yaml.js /usr/local/bin/gosu \
        /usr/local/bin/docker-entrypoint.sh /var/lib/apt/lists/*; \
    test -x /usr/bin/mongod; \
    test -x /usr/bin/mongosh; \
    mongod --version
USER 999:999
ENTRYPOINT ["mongod"]
