# Operations and interview demonstration

## Observe

Use Argo CD to match desired Git revision, image version, sync status, and health.
Use the Grafana dashboard `Purely — release health` for traffic, HTTP 5xx,
95th-percentile latency, ready pods, CPU, and memory. Metrics panels require traffic;
an empty latency panel is not evidence that the application is healthy.
Prometheus rules detect a down target, absent product monitoring, and an unavailable
deployment. Alertmanager routes the three Purely warning and critical alerts
to Slack channel `#all-purely-alerts` and sends a resolved notification when an
alert clears. The GitOps configuration references the Kubernetes Secret
`monitoring/purely-slack-webhook`, key `url`. Provision that Secret before
applying the monitoring Application on a fresh cluster. Keep its value out of Git.

## Release to AKS

1. Merge the application PR after the Validate workflow passes.
2. Run **Build approved release** on `master` and record the source commit SHA.
   The workflow tests, scans, and publishes images tagged with that SHA.
3. Review the generated GitOps PR. Check that its image tag changes match the
   approved release, then merge it and watch Argo CD reconcile.
4. Verify the deployed images and readiness, then open the public catalog,
   click a product, and verify its description and price. Use a reserved demo
   account for cart and order smoke tests.

If the build reports `Release tag already exists`, look for the existing
`gitops/release-<sha>` PR and its successful run. Published release tags are
immutable. Review the existing promotion before starting another release.

## Recover

For a bad release, create a revert PR for the GitOps promotion merge. If later
promotions touched the same charts, prepare a targeted PR restoring the intended
previous image tags. Check that those images exist in ACR and review the diff.
After merge, confirm that Argo CD is Synced and Healthy at the new Git revision
and that the intended previous images are running. Repeat the public smoke tests.
To return to the newer version, promote the verified newer tags through a new PR.

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

## Verified demo evidence

| Drill | Observed result |
| --- | --- |
| Release and browser smoke test | GitOps PR #15 promoted `faba2c50`. The public Yoga Mat card opened its detail page with the description, price, and bag button. |
| Frontend pod eviction | Kubernetes restored the frontend in 8.28 seconds. All 13 HTTPS probes succeeded during the drill. |
| GitOps rollback and restore | PR #12 rolled back the frontend image and PR #13 restored the newer image. Both deployment checks reported the expected images, Synced and Healthy, and public HTTPS 200. |
| MongoDB restore | Five encrypted archives restored into an isolated MongoDB instance and matched the source fingerprints. |
| Alert delivery | On 2026-11-09, Prometheus fired `PurelyDeliveryDrill`. Alertmanager sent it to a temporary ClusterIP webhook, which recorded the matching drill ID and returned HTTP 204. |

For another delivery drill, create a temporary PrometheusRule with
`release: monitoring`, a unique drill label, and a synthetic expression.
Use an AlertmanagerConfig matching both the alert name and drill label, and
route only that alert to a temporary in-cluster webhook. Confirm the matching
firing payload at the receiver, then remove the rule, route, service, and pod.

### Public endpoint baseline

On 2026-11-09, Windows PowerShell sent 60 read-only HTTPS requests from the
operator workstation with at most two concurrent requests and an eight-second
timeout. Timings include client and network overhead. Percentiles below include
attempts that reached the timeout.

| Route | HTTP 200 | Timed-out attempts | p50 | p95 |
| --- | ---: | ---: | ---: | ---: |
| `/products/All` | 28/30 | 2 | 6.24 s | 8.00 s |
| `/product-service/product/get/all` | 29/30 | 1 | 6.18 s | 7.70 s |

One in-test pod sample showed 1 millicore and 5–6 MiB per frontend
replica, 8–9 millicores and 224 MiB per gateway replica, and 11–12
millicores and 247–249 MiB per product replica. These are point measurements.
This run records a baseline with 3 of 60 unsuccessful attempts. Compare
public timings with an in-cluster probe and server-side latency before assigning
the delay to a specific component.

### Follow-up from AKS

From a frontend pod, ten HTTPS requests per route succeeded through the
internal frontend Service, and ten more per route succeeded through the public
hostname. Both probes retained normal TLS certificate validation. With ten
samples per group, the nearest-rank p95 is the slowest sample.

| Route | Internal Service p95 | Public hostname from AKS p95 |
| --- | ---: | ---: |
| `/products/All` | 97 ms | 98 ms |
| `/product-service/product/get/all` | 112 ms | 119 ms |

The Windows slowdown did not reproduce from AKS, including via the public
hostname. These were separate samples with different clients. An independent
external probe is needed to separate workstation behavior from internet-path
latency.

Prometheus recorded an approximate server-side p95 of 18 ms for GET
`/product/get/all` in the product service over a 30-minute window. This
histogram estimate covers service handling and is separate from the HTTPS
probe timings.
