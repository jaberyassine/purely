FROM certbot/certbot:v5.9.0
USER root
RUN apk upgrade --no-cache
COPY warmup.py issue.sh /opt/purely/
RUN /bin/sh -n /opt/purely/issue.sh && python -m py_compile /opt/purely/warmup.py
USER 10001:10001
