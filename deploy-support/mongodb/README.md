# Temporary Purely database

`Prepare-PurelyDatabase.ps1` in the operator workspace builds and scans this
dedicated server image, publishes it to the demo ACR, and installs the chart at
`k8s/data/mongodb` using an immutable digest. It never installs the application
charts.

The database requires TLS and SCRAM authentication. An internal CA and six
application users are generated locally. Five accounts have read/write access
to their own databases. The legacy user-service reads identities created by
auth-service: its separate account authenticates in `purely_user` and has only
`find` on `purely_auth.Users`, without writes or access to `Roles`. Only public CA
certificates are placed in application truststores; the CA private key stays on
the operator machine. Secrets are sent to Kubernetes over stdin rather than
placed in Helm values or Git. Bootstrap credentials are retained in an excluded,
ACL-restricted local directory for recovery and idempotent reruns.

The script checks the five owners' read/write access, denial of cross-database reads,
and the identity reader's collection scope,
and survival of a marker through a database pod restart. The 16Gi Azure Disk
PVC is retained when the StatefulSet is removed. Removing a namespace or PVC
still removes storage according to the StorageClass policy.

This is a single-instance database for a temporary demonstration, with no
replication or automatic failover. The pod restart check verifies persistence;
it does not verify backups or restoration. Do not represent this as a
production MongoDB cluster. NetworkPolicy enforcement is not assumed: the
current Terraform configuration does not enable a network policy engine.

Internal certificates expire after fourteen days. They are not public frontend
certificates. Database bootstrap uses MongoDB's documented localhost exception
to create the first administrator while access control and TLS remain enabled.

`Finish-PurelyDemo.ps1` migrates the previously deployed user-service account
from its unused database to this collection-scoped role, updates its runtime
Secret and restarts only user-service. It then creates reserved example.invalid
fixtures, tests Mailpit verification, provisions one operator-owned demo admin,
and verifies catalog, cart, checkout, cancellation and ownership denials. Reports
contain no passwords or JWTs. Credentials remain in the private runtime directory.
