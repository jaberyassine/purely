# Internal demonstration mailbox

The temporary Purely deployment captures application mail in Mailpit rather
than contacting real recipients. No relay or forwarding is configured.

`Prepare-PurelyMailbox.ps1` builds and scans the dedicated image before ACR
publication, pins the immutable digest in the Helm installation, generates
independent SMTP/UI credentials, and signs the server certificate with the
existing internal CA. Both the mailbox UI/API and SMTP require authentication;
SMTP requires STARTTLS, and the UI/API uses HTTPS. Kubernetes exposes only a
ClusterIP Service. Captured mail uses a retained 4Gi Azure Disk PVC.

Verification uses temporary port forwards bound only to 127.0.0.1. It checks
the CA and certificate hostname, rejects SMTP authentication before TLS,
rejects an incorrect password, requires mailbox API authentication, and checks
that an authenticated SMTP message is captured. The script stops only the
port-forward process it started. It does not display credentials.

The application chart changes mount a read-only truststore containing the
standard Java roots plus the internal CA. The password `changeit` protects a
truststore of public CA certificates, not private keys. Notification settings
also enable SMTP certificate hostname verification.

Application charts must be merged before Argo CD is allowed to deploy them.
Existing release image references remain unchanged; no application image
rebuild is required for these Helm environment and volume changes.
