# Temporary frontend HTTPS bootstrap

`Prepare-PurelyFrontendTls.ps1` creates the frontend LoadBalancer with an Azure
DNS label, verifies the actual FQDN/IP mapping, and runs a scanned non-root
Certbot image at an immutable ACR digest. A temporary port-80 backend returns
only 404 until Certbot serves the ACME HTTP-01 challenge. It never serves
application files, database credentials or private key files.

The job first validates issuance against the staging CA, then obtains a public
certificate from the production CA. The operator checks the trusted chain,
hostname and certificate/private-key match before creating `frontend/purely-tls`.
The temporary job is deleted after extraction. Private keys remain in the
excluded ACL-restricted local runtime directory and the Kubernetes TLS Secret.

The later application bootstrap must replace the Service's port-80 challenge
mapping with the Helm-defined HTTPS mapping using the same bootstrap field
manager, before applying the frontend Argo CD Application. It must preserve
the existing Service/IP and DNS annotation.

This is a one-time certificate bootstrap for the temporary demo. It does not
claim automatic renewal. The final runbook must record certificate expiry;
the demo must end before expiry or have a separate verified renewal procedure.
The public frontend certificate is separate from the internal MongoDB/SMTP CA.

The initial Trivy scan found five HIGH findings in pip's bundled msgpack 1.1.2,
urllib3 2.7.0 and pkg_resources/setuptools 70.3.0. The normal runtime copies of
urllib3 and setuptools were already patched. The image removes the unneeded
pip installer and all its vendored code. Build checks require pip to be absent
and Certbot/plugin discovery to work as the non-root runtime user. No SBOMs,
scanner rules or vulnerability exceptions are edited.

After the configuration PR is merged, `Start-PurelyApplication.ps1` fetches
master, checks the runtime Secrets and ready database/mailbox, then applies
the monitoring Application before any app ServiceMonitors. It starts Eureka
first, reconciles the backend Applications, transfers the existing frontend
Service to the HTTPS mapping, and starts the frontend. The final smoke check
validates public TLS/HTML/HSTS, blocked actuator routes and Prometheus UP
targets across all nine backend namespaces. Business flows still require their
own end-to-end verification.
