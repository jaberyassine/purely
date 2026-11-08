# Temporary Purely database

`Prepare-PurelyDatabase.ps1` in the operator workspace builds and scans this
dedicated server image, publishes it to the demo ACR, and installs the chart at
`k8s/data/mongodb` using an immutable digest. It never installs the application
charts.

The database requires TLS and SCRAM authentication. An internal CA and six
database-scoped application users are generated locally. Only public CA
certificates are placed in application truststores; the CA private key stays on
the operator machine. Secrets are sent to Kubernetes over stdin rather than
placed in Helm values or Git. Bootstrap credentials are retained in an excluded,
ACL-restricted local directory for recovery and idempotent reruns.

The script checks per-user read/write access, denial of cross-database reads,
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
