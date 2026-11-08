FROM certbot/certbot:v5.9.0
USER root
RUN apk upgrade --no-cache
# pip is a build/install tool, not a Certbot runtime dependency. Its bundled
# msgpack, urllib3 and pkg_resources contain the reported vulnerable copies.
# Remove the installer and its actual vendored code, rather than editing SBOMs.
RUN python -m pip uninstall --yes pip \
    && python -c "import importlib.util; assert importlib.util.find_spec('pip') is None"
COPY warmup.py issue.sh /opt/purely/
RUN /bin/sh -n /opt/purely/issue.sh && python -m py_compile /opt/purely/warmup.py
USER 10001:10001
RUN mkdir -p /tmp/certbot-self-test \
    && certbot --version \
    && certbot plugins --authenticators \
        --config-dir /tmp/certbot-self-test/config \
        --work-dir /tmp/certbot-self-test/work \
        --logs-dir /tmp/certbot-self-test/logs > /tmp/certbot-self-test/plugins.txt \
    && grep -Fq 'standalone' /tmp/certbot-self-test/plugins.txt \
    && rm -rf /tmp/certbot-self-test
