# mlflow

![Version: 0.0.1](https://img.shields.io/badge/Version-0.0.1-informational?style=flat-square) ![AppVersion: 3.18.0](https://img.shields.io/badge/AppVersion-3.18.0-informational?style=flat-square)

This chart deploys [MLflow](https://github.com/mlflow/mlflow), an open source platform to manage the machine learning lifecycle. It runs the MLflow **tracking server and model registry**: it records the parameters, metrics and artifacts of training runs, groups them into experiments, and keeps versioned registered models that other services can download and serve.

The chart is designed to be used on its own or as an optional dependency of other ERTIS charts that need an MLflow server (for example a training platform that logs runs, or a model-serving platform that deploys registered models). It deliberately keeps a simple, single-replica setup:

- The **backend store** (experiments, runs, registered models) is a SQLite database on a `PersistentVolumeClaim`.
- The **artifacts** (model files, plots, datasets logged by runs) are always served by MLflow itself (`--serve-artifacts`), so clients only need the tracking URI. They are stored either on the same volume (`local`) or in a bucket of an S3-compatible object storage such as MinIO (`s3`).

## What the chart creates

All resource names are derived from the release name (`<release>-mlflow`, or just `<release>` when the release name already contains `mlflow`, e.g. `mlflow` or `mlflow-dev`), so several releases can be installed in the same namespace. The examples below use `<release>-mlflow`.

- A `Deployment` with a single MLflow replica (official image `ghcr.io/mlflow/mlflow:v3.18.0-full`, port `5000`) using the `Recreate` strategy, since SQLite allows a single writer.
- A `Service` exposing it. The tracking URI inside the cluster is `http://<release>-mlflow.<namespace>:5000`.
- A `PersistentVolumeClaim` (`<release>-mlflow-data`) mounted at `/mlflow`, unless `persistence.existingClaim` is set or persistence is disabled.
- With `artifacts.backend=s3`:
  - An init container that creates the bucket if it does not exist (`artifacts.s3.createBucket`).
  - A `Secret` (`<release>-mlflow-s3`), only when the S3 credentials are given as plain values instead of `artifacts.s3.existingSecret`.
- Optionally an `Ingress` or a Gateway API `HTTPRoute`.
- Optionally a MinIO server (`minio.enabled`, disabled by default). It is deployed from the [cloudpirates/minio](https://artifacthub.io/packages/helm/cloudpirates-minio/minio) `~0.14.0` subchart and named `<release>-minio`. When it is enabled, MLflow automatically uses the `s3` backend:
  - It connects to `http://<release>-minio:9000`.
  - It reads the credentials from the MinIO Secret.
  - It creates the bucket `artifacts.s3.bucket` at start-up.

The `-full` image is used because the plain MLflow image does not include `boto3`, which is required to store artifacts in S3/MinIO.

## Prerequisites

- A Kubernetes cluster with a default `StorageClass` (or set `persistence.storageClass`).
- [Helm](https://helm.sh/) 4.
- For `artifacts.backend=s3`: an S3-compatible object storage reachable from the pod, and credentials allowed to read and write the bucket (and to create it, if `artifacts.s3.createBucket` is `true`).

## Installation

Add the ERTIS Research Helm repository and update the local index:

```bash
helm repo add ertis https://ertis-research.github.io/helm-charts/
helm repo update
```

Install MLflow with SQLite and local artifacts on the persistent volume (replace `<release>` and `<namespace>`):

```bash
helm upgrade --install <release> ertis/mlflow -n <namespace> --create-namespace
```

Store the artifacts in a MinIO server deployed by the same release:

```bash
helm upgrade --install <release> ertis/mlflow -n <namespace> --create-namespace --set minio.enabled=true
```

Store the artifacts in an existing S3-compatible object storage, with the credentials in an existing Secret:

```yaml
artifacts:
  backend: s3
  s3:
    endpoint: "<scheme>://<object-storage-host>:<port>"
    bucket: mlflow
    existingSecret: "<secret-with-s3-credentials>"   # keys: access-key, secret-key
```

```bash
helm upgrade --install <release> ertis/mlflow -n <namespace> --create-namespace -f my-values.yaml --rollback-on-failure
```

Access the UI from your machine:

```bash
kubectl -n <namespace> port-forward svc/<release>-mlflow 5000:5000
```

Then open `http://localhost:5000`.

## Using the chart as a dependency

Declare it in the parent `Chart.yaml` with a condition so it stays optional:

```yaml
dependencies:
  - name: mlflow
    version: 0.0.1
    repository: https://ertis-research.github.io/helm-charts/
    condition: mlflow.enabled
```

When used as a subchart, its resources are named `<release>-mlflow`, and the parent can build the tracking URI as `http://{{ .Release.Name }}-mlflow:{{ .Values.mlflow.service.port }}`.

If the parent chart does not have an object storage of its own, it can simply set `mlflow.minio.enabled: true`.

If the parent chart already deploys its own object storage, keep `mlflow.minio.enabled: false` and point MLflow to it. The values `artifacts.s3.endpoint`, `artifacts.s3.existingSecret`, `persistence.existingClaim` and `extraAllowedHosts` are rendered with `tpl`, so no names need to be hardcoded. For example, with a cloudpirates MinIO subchart in the parent:

```yaml
mlflow:
  enabled: true
  artifacts:
    backend: s3
    s3:
      endpoint: "http://{{ .Release.Name }}-minio:9000"
      existingSecret: "{{ .Release.Name }}-minio"
      accessKeyKey: root-user
      secretKeyKey: root-password
```

## Notes

- **Host validation.** MLflow 3 rejects requests whose `Host` header is not allowed (HTTP 403). The chart allows these hosts automatically through `MLFLOW_SERVER_ALLOWED_HOSTS`:
  - the in-cluster Service names;
  - `localhost`;
  - the `ingress.hosts`;
  - the `httpRoute.hostnames`.

  If you reach MLflow through any other hostname or address (a `NodePort`, a `LoadBalancer` IP, or an Ingress managed outside the chart), add it to `extraAllowedHosts`. The probes send `Host: localhost` for the same reason. MLflow does not validate the host on `/health`, so a `200` there does not mean the UI and API accept that host.
- **Authentication.** MLflow has no authentication by default. Anyone who can reach the Service, Ingress or HTTPRoute can read and modify experiments and models. Keep the default `ClusterIP` Service, or protect the exposed endpoint.
- **Single replica.** The SQLite backend store allows a single writer, so the replica count is fixed to `1` and cannot be configured.
- **Persistence.** With `persistence.enabled=false`, everything is lost when the pod restarts: the experiments, runs and registered models, plus the artifacts when `artifacts.backend=local`.
- **Self-signed object storage.** If the object storage uses a self-signed certificate, add `MLFLOW_S3_IGNORE_TLS=true` with `extraEnv`.

## Uninstallation

```bash
helm uninstall <release> -n <namespace>
```

This deletes the resources created by the chart, including the `PersistentVolumeClaim`s created by the chart and by the bundled MinIO. The MLflow metadata and the artifacts stored on the volume or in the bundled MinIO are therefore lost. Objects stored in an external S3 bucket and a PVC given in `persistence.existingClaim` are not deleted.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| image.repository | string | `"ghcr.io/mlflow/mlflow"` | MLflow container image repository. The image must include `boto3` when `artifacts.backend` is `s3`, which is why the official `-full` variant is used by default. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. `IfNotPresent` pulls the image only if it is not cached on the node, `Always` pulls it on every pod start, and `Never` only uses an image already present on the node. |
| image.tag | string | `""` | Image tag. Leave empty to use `v<appVersion>-full`. |
| imagePullSecrets | list | `[]` | References to `kubernetes.io/dockerconfigjson` Secrets used to pull the image from a private registry. They must already exist in the release namespace. |
| nameOverride | string | `""` | Overrides the chart name used in resource names and the `app.kubernetes.io/name` label. |
| fullnameOverride | string | `""` | Fully overrides the name of the resources created by this chart. Changing it on an existing release creates a new PVC. |
| artifacts.backend | string | `"local"` | Where the artifacts are stored. `local` uses the same volume as the SQLite database (`/mlflow/artifacts`). `s3` uses a bucket of an S3-compatible object storage configured in `artifacts.s3`. MLflow always serves them through its own API. Ignored when `minio.enabled` is `true` (`s3` with the bundled MinIO is used). |
| artifacts.s3.endpoint | string | `""` | URL of the external object storage, including the scheme (`MLFLOW_S3_ENDPOINT_URL`). Required when `artifacts.backend` is `s3` and `minio.enabled` is `false`. Rendered with `tpl`. |
| artifacts.s3.bucket | string | `"mlflow"` | Bucket where the artifacts are stored. Required when `artifacts.backend` is `s3`. |
| artifacts.s3.createBucket | bool | `true` | Create the bucket at start-up if it does not exist, with an init container that retries for up to five minutes. Requires credentials allowed to create buckets. |
| artifacts.s3.existingSecret | string | `""` | Existing Secret with the S3 credentials. Rendered with `tpl`. If set, `accessKey` and `secretKey` are ignored and no Secret is created. |
| artifacts.s3.accessKeyKey | string | `"access-key"` | Key of the access key ID inside the credentials Secret. |
| artifacts.s3.secretKeyKey | string | `"secret-key"` | Key of the secret access key inside the credentials Secret. |
| artifacts.s3.accessKey | string | `""` | Access key of the object storage. Set together with `secretKey` to let the chart create the `<fullname>-s3` Secret. Either `existingSecret` or both keys are required for an external object storage. |
| artifacts.s3.secretKey | string | `""` | Secret key of the object storage. Prefer `existingSecret`. |
| extraAllowedHosts | list | `[]` | Additional `Host` headers accepted by MLflow (`MLFLOW_SERVER_ALLOWED_HOSTS`). The Service names, `localhost`, the Ingress hosts and the HTTPRoute hostnames are always allowed. Each entry is rendered with `tpl`. |
| extraArgs | list | `[]` | Additional arguments appended to `mlflow server`. Do not set the host, port, backend store or artifact options. |
| extraEnv | list | `[]` | Additional environment variables of the MLflow container, as Kubernetes `EnvVar` objects. |
| podAnnotations | object | `{}` | Annotations added to the MLflow pod. |
| podLabels | object | `{}` | Labels added to the MLflow pod. |
| podSecurityContext | object | `{}` | Pod-level security context. Empty by default because the official image runs as root. |
| securityContext | object | `{}` | Container-level security context, applied to MLflow and to the bucket initialization container. |
| service.type | string | `"ClusterIP"` | Service type. `ClusterIP` exposes MLflow only inside the cluster, `NodePort` also exposes it on every node using `service.nodePort`, and `LoadBalancer` requests an external load balancer. |
| service.port | int | `5000` | Service port. The container always listens on port 5000. |
| service.nodePort | string | `""` | Node port used when `service.type` is `NodePort` or `LoadBalancer`. Leave empty to let Kubernetes assign one. |
| ingress.enabled | bool | `false` | Create an Ingress. Requires an ingress controller and at least one entry in `ingress.hosts`. |
| ingress.className | string | `""` | Ingress class name. Leave empty to use the cluster default class. |
| ingress.annotations | object | `{}` | Annotations added to the Ingress. |
| ingress.hosts | list | `[]` | Hosts and paths routed to MLflow (`host` and `paths` with `path` and `pathType`). |
| ingress.tls | list | `[]` | TLS configuration (`secretName` and `hosts`). |
| httpRoute.enabled | bool | `false` | Create a Gateway API HTTPRoute. Requires the Gateway API CRDs and an existing Gateway in `httpRoute.parentRefs`. |
| httpRoute.annotations | object | `{}` | Annotations added to the HTTPRoute. |
| httpRoute.parentRefs | list | `[]` | Gateways this route is attached to. |
| httpRoute.hostnames | list | `[]` | Hostnames matched by the route. If empty, add the public hostname to `extraAllowedHosts`. |
| httpRoute.rules | list | `[{"matches":[{"path":{"type":"PathPrefix","value":"/"}}]}]` | Routing rules; all rules are sent to the MLflow Service. |
| persistence.enabled | bool | `true` | Store the SQLite database (and the local artifacts) in a PVC mounted at `/mlflow`. If `false`, an `emptyDir` is used and all data is lost when the pod restarts. |
| persistence.existingClaim | string | `""` | Use an existing PVC instead of creating one. Rendered with `tpl`. |
| persistence.storageClass | string | `""` | StorageClass of the created PVC. Leave empty to use the cluster default. |
| persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes of the created PVC. |
| persistence.size | string | `"1Gi"` | Requested size of the created PVC. Increase it when `artifacts.backend` is `local`. |
| resources | object | `{}` | CPU and memory requests and limits of the MLflow container (also applied to the bucket initialization container). |
| livenessProbe | object | HTTP `GET /health` with `Host: localhost` | Liveness probe. The `Host` header is required by the MLflow 3 host validation. |
| readinessProbe | object | HTTP `GET /health` with `Host: localhost` | Readiness probe. |
| minio.enabled | bool | `false` | Deploy a MinIO server (`<release>-minio`) and store the artifacts in it. MLflow then uses the `s3` backend with the MinIO endpoint and credentials automatically; only `artifacts.s3.bucket` and `artifacts.s3.createBucket` are used. Any other value of the subchart can be set under `minio`. |
| minio.auth.rootUser | string | `"admin"` | MinIO root user, used by MLflow as access key. |
| minio.auth.rootPassword | string | `""` | MinIO root password. Leave empty to generate a random one (kept across upgrades) in the `<release>-minio` Secret. |
| nodeSelector | object | `{}` | Node labels used to schedule the MLflow pod. |
| tolerations | list | `[]` | Tolerations of the MLflow pod. |
| affinity | object | `{}` | Affinity rules of the MLflow pod. |
