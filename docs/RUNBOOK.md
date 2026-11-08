# Operations and interview demonstration

## Observe

Use Argo CD to match desired Git revision, image version, sync status, and health.
Use the Grafana dashboard `Purely — release health` for traffic, HTTP 5xx,
95th-percentile latency, ready pods, CPU, and memory. Metrics panels require traffic;
an empty latency panel is not evidence that the application is healthy.
Prometheus rules detect a down target, absent product monitoring, and an unavailable
deployment. External alert notification routing is intentionally not configured.

## Recover

For a bad release, revert the reviewed release merge in Git and merge the revert.
Confirm that Argo CD reconciles the old image SHA and that application smoke tests
pass. Do not rely on `kubectl rollout undo` as the durable rollback while Git still
requests the bad version. No automatic rollback is claimed.

For drift, compare the live resource with Git, check the Argo CD activity log, and
confirm self-heal restores the desired settings. This is different from Kubernetes
replacing a failed pod. Investigate first; do not randomly restart all services.

## Rehearse in an isolated demo environment

1. Show architecture and your personal contribution (45 seconds).
2. Show a failed test blocking an example PR (recorded evidence is acceptable).
3. Release a small visible change; identify its Git SHA in the image and Argo CD.
4. Generate a small bounded workload; show the dashboard responding.
5. With two healthy product replicas, delete one selected product pod. Measure
   successful/failed requests and replacement time; do not claim zero downtime
   without the measured result. A node failure is a different test.
6. Demonstrate drift correction by temporarily changing a safe deployment setting
   in the demo environment, then show Argo CD restoring Git's desired value.
7. Revert a release through Git; measure recovery and run functional smoke tests.

Record outcomes, timestamps, limitations, and a short backup video. Keep the live
interview demonstration around six minutes; full Java/image builds may take longer,
so prepare a successful run and release history beforehand.

## Availability limits

Only product, gateway, and frontend are replicated by default. Auth, registry,
and other services remain single-replica. PDBs protect selected voluntary disruptions;
they do not prevent hardware failure. Spreading is preferred, not mandatory.
An AKS cluster, Mongo database, and backups have separate availability concerns.
