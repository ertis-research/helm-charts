# kmlops

![Version: 0.0.1](https://img.shields.io/badge/Version-0.0.1-informational?style=flat-square) ![AppVersion: 0.0.1](https://img.shields.io/badge/AppVersion-0.0.1-informational?style=flat-square)

This chart deploys [kMLOps](https://github.com/ertis-research/kmlops) (Kubernetes MLOps), a lightweight MLOps service that turns a Kubernetes cluster into a model training platform. Users upload a CSV dataset and describe the model in a declarative [Ludwig](https://ludwig.ai) configuration through a REST API. kMLOps stores the dataset in MinIO, runs the training as an isolated Kubernetes Job, and records metrics, parameters, artifacts and model versions in [MLflow](https://mlflow.org). It also exposes a single API to list, inspect and delete experiments and runs of the whole MLflow tracking server.

kMLOps is the MLOps component of [OpenTwins](https://github.com/ertis-research/opentwins), but it has no dependency on it and can be deployed on its own.

## What the chart creates

All resource names are derived from the release name, so several releases can be installed in the same namespace.

- A `Deployment` running the kMLOps API (FastAPI, port `8000`) and a `Service` exposing it (`<release>-kmlops`). Optionally an `Ingress` or a Gateway API `HTTPRoute`.
- A `ServiceAccount`, plus a `Role` and `RoleBinding` that let kMLOps create, watch and delete the training `Job`s and read their pods and logs in the release namespace. Training Jobs always run in the release namespace.
- The training store: a `PersistentVolumeClaim` for the SQLite database (default), or a connection to PostgreSQL.
- A `Secret` with the credentials of external MinIO/PostgreSQL servers, only when they are provided as plain values.
- An MLflow tracking server (`<release>-mlflow`, enabled by default), deployed with the [ertis/mlflow](https://github.com/ertis-research/helm-charts/tree/main/mlflow) chart as a dependency: a `Deployment`, a `Service` and a `PersistentVolumeClaim` running the official [MLflow](https://github.com/mlflow/mlflow) image (`ghcr.io/mlflow/mlflow:v3.18.0-full`). It stores its metadata in SQLite on the volume and serves the artifacts (`--serve-artifacts`) from the `mlflow` bucket of the bundled MinIO, which it creates if it does not exist. The training Jobs therefore only need the MLflow tracking URI.
- Optional dependencies, each of which can be replaced by an external server:

| Component | Source | Default | Purpose | External alternative |
|-----------|--------|---------|---------|----------------------|
| MinIO | [cloudpirates/minio](https://artifacthub.io/packages/helm/cloudpirates-minio/minio) `~0.14.0` (`<release>-minio`) | enabled (`minio.enabled`) | Datasets and MLflow artifacts | `externalMinio.*` |
| PostgreSQL | [cloudpirates/postgres](https://artifacthub.io/packages/helm/cloudpirates-postgres/postgres) `~0.22.1` (`<release>-postgres`) | disabled (`postgres.enabled`) | kMLOps training store | `database.backend=postgres` + `externalPostgresql.*` |
| MLflow | [ertis/mlflow](https://github.com/ertis-research/helm-charts/tree/main/mlflow) `0.0.1` (`<release>-mlflow`) | enabled (`mlflow.enabled`) | Tracking server and model registry | `externalMlflow.trackingUri` |

## Prerequisites

- A Kubernetes cluster with a default `StorageClass` (or set the `storageClass` values) for the persistent volumes.
- [Helm](https://helm.sh/) 4.
- Training pods pull the Ludwig image (`training.image`) and install Python packages with `pip` at start-up, so they need access to the image registry and to a Python package index.

## Installation

Add the ERTIS Research Helm repository and update the local index:

```bash
helm repo add ertis https://ertis-research.github.io/helm-charts/
helm repo update
```

Install the chart with the bundled MinIO and MLflow and the SQLite training store (replace `<namespace>`). The examples use `kmlops` as release name, so the main resources are named `kmlops`, `kmlops-minio` and `kmlops-mlflow`; choose another name to install several releases in the same namespace:

```bash
helm upgrade --install kmlops ertis/kmlops -n <namespace> --create-namespace
```

Use the bundled PostgreSQL as training store instead of SQLite:

```bash
helm upgrade --install kmlops ertis/kmlops -n <namespace> --create-namespace \
  --set postgres.enabled=true
```

Connect to external services instead of the bundled ones, with a values file such as:

```yaml
minio:
  enabled: false
mlflow:
  enabled: false
externalMinio:
  endpoint: "<minio-host>:<port>"
  secure: true
  existingSecret: "<secret-with-minio-credentials>"   # keys: access-key, secret-key
externalMlflow:
  trackingUri: "<mlflow-tracking-uri>"
database:
  backend: postgres
externalPostgresql:
  host: "<postgres-host>"
  database: "<database>"
  user: "<user>"
  existingSecret: "<secret-with-postgres-password>"   # key: password
```

```bash
helm upgrade --install kmlops ertis/kmlops -n <namespace> --create-namespace -f my-values.yaml
```

Notes:

- The bundled MLflow can also be combined with an external MinIO/S3 server: keep `mlflow.enabled=true`, configure `externalMinio` and point MLflow to the same server. The MLflow subchart cannot read the kMLOps values, so its object storage is configured separately in `mlflow.artifacts.s3`. By default it points to the bundled MinIO, and rendering fails if `minio.enabled` is `false` and those defaults are kept. MLflow creates its `mlflow.artifacts.s3.bucket` bucket there:

  ```yaml
  minio:
    enabled: false
  externalMinio:
    endpoint: "<minio-host>:<port>"
    secure: true
    existingSecret: "<secret-with-minio-credentials>"   # keys: access-key, secret-key
  mlflow:
    artifacts:
      s3:
        endpoint: "https://<minio-host>:<port>"         # URL with scheme
        existingSecret: "<secret-with-minio-credentials>"
        accessKeyKey: access-key
        secretKeyKey: secret-key
  ```

  Alternatively, set `mlflow.artifacts.backend=local` to keep the MLflow artifacts on the MLflow volume.
- An external MLflow server must serve artifacts itself (`--serve-artifacts`), because the training Jobs only receive the tracking URI.
- MLflow 3 rejects requests whose `Host` header is not allowed (HTTP 403). The in-cluster Service names and `localhost` are allowed by default; if you expose the MLflow UI through your own Ingress or hostname, add it to `mlflow.extraAllowedHosts`.
- All the options of the bundled MLflow (persistence, resources, Ingress, extra allowed hosts...) are documented in the [ertis/mlflow README](https://github.com/ertis-research/helm-charts/tree/main/mlflow) and can be set under the `mlflow` key.

After the installation, follow the instructions printed by Helm to reach the API. Its interactive documentation is available at `/docs`.

## Uninstallation

```bash
helm uninstall kmlops -n <namespace>
```

This deletes the resources created by the chart and its dependencies, including the persistent volume claims of the SQLite training store, the MLflow metadata and the MinIO data, so that data is lost. A claim given in `mlflow.persistence.existingClaim` is not deleted. The volume claim of the bundled PostgreSQL is created by its StatefulSet and is **not** deleted; remove it manually if you no longer need it:

```bash
kubectl delete pvc -n <namespace> -l app.kubernetes.io/instance=kmlops,app.kubernetes.io/name=postgres
```

## Values

The documentation of every value of the dependencies can be found in their charts: [MinIO](https://artifacthub.io/packages/helm/cloudpirates-minio/minio), [PostgreSQL](https://artifacthub.io/packages/helm/cloudpirates-postgres/postgres) and [MLflow](https://github.com/ertis-research/helm-charts/tree/main/mlflow). Any of them can be set under the `minio`, `postgres` and `mlflow` keys. The table lists the values set by this chart.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `replicaCount` | int | `1` | Number of kMLOps API replicas. Must be `1` when `database.backend` is `sqlite` (SQLite allows a single writer and the data volume is `ReadWriteOnce`); rendering fails otherwise. Use `postgres` as the training store to run more than one replica. |
| `image.repository` | string | `"docker.ertis.uma.es/kmlops/kmlops"` | Container image repository of the kMLOps API. |
| `image.pullPolicy` | string | `"IfNotPresent"` | Image pull policy. `IfNotPresent` pulls the image only if it is not cached on the node, `Always` pulls it on every pod start, and `Never` only uses an image already present on the node. |
| `image.tag` | string | `""` | Image tag. Leave empty to use the chart `appVersion`. |
| `imagePullSecrets` | list | `[]` | References to Secrets of type `kubernetes.io/dockerconfigjson` used to pull the kMLOps image from a private registry. Example: `[{name: my-registry-credentials}]`. The Secrets must already exist in the release namespace. |
| `nameOverride` | string | `""` | Overrides the chart name used in resource names and the `app.kubernetes.io/name` label. |
| `fullnameOverride` | string | `""` | Fully overrides the name of the resources created by this chart (Deployment, Service, Role, PVC...). |
| `serviceAccount.create` | bool | `true` | Create a dedicated ServiceAccount for kMLOps. kMLOps uses it to create and watch the training Jobs, so it must be bound to the Role created when `rbac.create` is `true`. |
| `serviceAccount.automount` | bool | `true` | Mount the ServiceAccount API token in the pod. Must stay `true`: kMLOps calls the Kubernetes API with it. |
| `serviceAccount.annotations` | object | `{}` | Annotations added to the ServiceAccount. |
| `serviceAccount.name` | string | `""` | Name of the ServiceAccount. If empty and `serviceAccount.create` is `true`, a name is generated from the release name. If `serviceAccount.create` is `false`, this existing ServiceAccount is used (or `default` if empty). |
| `rbac.create` | bool | `true` | Create a Role and RoleBinding in the release namespace that allow the ServiceAccount to create, get, list, watch and delete Jobs, and to read pods and their logs. Without these permissions kMLOps cannot launch, monitor or cancel trainings. Set to `false` only if equivalent permissions are granted elsewhere. |
| `podAnnotations` | object | `{}` | Annotations added to the kMLOps pod. |
| `podLabels` | object | `{}` | Labels added to the kMLOps pod. |
| `podSecurityContext` | object | `{}` | Pod-level security context (e.g. `fsGroup`, `runAsUser`). Empty by default because the image runs as root; set `fsGroup` if you run it as a non-root user so it can write to the data volume. |
| `securityContext` | object | `{}` | Container-level security context (e.g. `capabilities`, `readOnlyRootFilesystem`, `runAsNonRoot`). Note that kMLOps writes its SQLite database under `/data` and Python caches inside the container. |
| `service.type` | string | `"ClusterIP"` | Kubernetes Service type used to expose the kMLOps API. `ClusterIP` exposes it only inside the cluster, `NodePort` also exposes it on every node using `service.nodePort`, and `LoadBalancer` requests an external load balancer from the cloud provider. |
| `service.port` | int | `8000` | Service port. The API container always listens on port 8000. |
| `service.nodePort` | string | `""` | Node port used when `service.type` is `NodePort` or `LoadBalancer`. Leave empty to let Kubernetes assign one. |
| `ingress.enabled` | bool | `false` | Create an Ingress for the kMLOps API. Requires an ingress controller in the cluster and at least one entry in `ingress.hosts`. |
| `ingress.className` | string | `""` | Ingress class name (e.g. `nginx`, `traefik`). Leave empty to use the cluster default class. |
| `ingress.annotations` | object | `{}` | Annotations added to the Ingress (e.g. for the ingress controller or cert-manager). |
| `ingress.hosts` | list | `[]` | Hosts and paths routed to the API. Each entry has `host` and a list of `paths` with `path` and `pathType` (`Prefix`, `Exact` or `ImplementationSpecific`). Example: `[{host: kmlops.example.org, paths: [{path: /, pathType: Prefix}]}]`. |
| `ingress.tls` | list | `[]` | TLS configuration. Each entry has `secretName` (an existing TLS Secret) and the list of `hosts` it covers. |
| `httpRoute.enabled` | bool | `false` | Create a Gateway API HTTPRoute for the kMLOps API. Requires the Gateway API CRDs and an existing Gateway referenced in `httpRoute.parentRefs`. |
| `httpRoute.annotations` | object | `{}` | Annotations added to the HTTPRoute. |
| `httpRoute.parentRefs` | list | `[]` | Gateways this route is attached to. Each entry has `name` and optionally `namespace` and `sectionName`. |
| `httpRoute.hostnames` | list | `[]` | Hostnames matched by the route. Leave empty to match any hostname accepted by the Gateway. |
| `httpRoute.rules` | list | `[{"matches":[{"path":{"type":"PathPrefix","value":"/"}}]}]` | Routing rules. Each rule has a list of `matches` and optional `filters`; all rules are sent to the kMLOps Service. |
| `resources` | object | `{}` | CPU and memory requests and limits of the kMLOps API container. Training workloads run in separate Jobs and are not affected. Example: `{requests: {cpu: 100m, memory: 256Mi}, limits: {memory: 1Gi}}`. |
| `livenessProbe` | object | `{"httpGet":{"path":"/","port":"http"},"initialDelaySeconds":30,"periodSeconds":20,"failureThreshold":3}` | Liveness probe of the API container. The kMLOps root endpoint `/` returns HTTP 200 when the API is running. |
| `readinessProbe` | object | `{"httpGet":{"path":"/","port":"http"},"initialDelaySeconds":5,"periodSeconds":10,"failureThreshold":3}` | Readiness probe of the API container. |
| `extraEnv` | list | `[]` | Additional environment variables for the API container, as a list of Kubernetes `EnvVar` objects (`name`/`value` or `valueFrom`). |
| `volumes` | list | `[]` | Additional volumes for the kMLOps pod. |
| `volumeMounts` | list | `[]` | Additional volume mounts for the API container. |
| `nodeSelector` | object | `{}` | Node labels used to schedule the kMLOps pod. |
| `tolerations` | list | `[]` | Tolerations of the kMLOps pod. |
| `affinity` | object | `{}` | Affinity rules of the kMLOps pod. |
| `training.image` | string | `"ludwigai/ludwig:0.17"` | Container image used by the training Jobs. It must contain Ludwig; the Job installs pinned versions of `minio` and `mlflow` (plus `training.extraPipPackages`) with pip at start-up, so the training pods need access to a Python package index. |
| `training.jobTtlSeconds` | int | `60` | Seconds after which Kubernetes deletes finished training Jobs and their pods. `0` deletes them immediately. |
| `training.backoffLimit` | int | `1` | Number of retries of a failed training pod before the Job is marked as failed. |
| `training.mlflowVersion` | string | `""` | Version of the `mlflow` Python package installed in the training pods (`TRAINING_MLFLOW_VERSION`), e.g. `3.18.0`. Leave empty to use the version pinned by kMLOps itself, which matches its own MLflow client. Keep it compatible with the MLflow server (the bundled one runs the `appVersion` of the ertis/mlflow chart unless `mlflow.image.tag` is set, or the external server). |
| `training.minioVersion` | string | `""` | Version of the `minio` Python package installed in the training pods (`TRAINING_MINIO_VERSION`). Leave empty to use the version pinned by kMLOps itself. |
| `training.extraPipPackages` | list | `[]` | Additional Python packages installed in the training pods (`TRAINING_PIP_EXTRA_PACKAGES`). Each entry must be exactly `name==version` (e.g. `scikit-learn==1.5.2`); any other format makes kMLOps fail at start-up. |
| `status.pollIntervalSeconds` | int | `10` | Interval in seconds at which kMLOps refreshes the status of active trainings from Kubernetes and MLflow. |
| `status.launchTimeoutSeconds` | int | `300` | A training still `queued` or `launching_job` after this many seconds is marked as `failed`. |
| `database.backend` | string | `"sqlite"` | Training store used by kMLOps. `sqlite` keeps the database in a file under `/data` (see `persistence`); it allows a single replica. `postgres` uses a PostgreSQL server: the bundled one when `postgres.enabled` is `true` (in that case `postgres` is selected automatically), or the server configured in `externalPostgresql`. |
| `persistence.enabled` | bool | `true` | Store the SQLite database in a PersistentVolumeClaim mounted at `/data`. Only used when the backend is `sqlite`. If `false`, an `emptyDir` is used and all trainings are lost when the pod is restarted. |
| `persistence.existingClaim` | string | `""` | Use an existing PersistentVolumeClaim instead of creating one. |
| `persistence.storageClass` | string | `""` | StorageClass of the created PVC. Leave empty to use the cluster default StorageClass. |
| `persistence.accessModes` | list | `["ReadWriteOnce"]` | Access modes of the created PVC. |
| `persistence.size` | string | `"1Gi"` | Requested size of the created PVC. |
| `bucketName` | string | `"kmlops"` | MinIO bucket where kMLOps stores the uploaded datasets. kMLOps creates it at start-up if it does not exist. |
| `externalMinio.endpoint` | string | `""` | Endpoint (`host:port`, without scheme) of an external MinIO or S3-compatible server. Required when `minio.enabled` is `false`; ignored otherwise. |
| `externalMinio.secure` | bool | `true` | Use HTTPS to connect to the external MinIO server. |
| `externalMinio.accessKey` | string | `""` | Access key of the external MinIO server. Stored in a Secret created by this chart. Ignored when `externalMinio.existingSecret` is set. |
| `externalMinio.secretKey` | string | `""` | Secret key of the external MinIO server. Stored in a Secret created by this chart. Ignored when `externalMinio.existingSecret` is set. |
| `externalMinio.existingSecret` | string | `""` | Name of an existing Secret containing the external MinIO credentials. Takes precedence over `accessKey`/`secretKey`. |
| `externalMinio.existingSecretAccessKeyKey` | string | `"access-key"` | Key of `externalMinio.existingSecret` holding the access key. |
| `externalMinio.existingSecretSecretKeyKey` | string | `"secret-key"` | Key of `externalMinio.existingSecret` holding the secret key. |
| `externalPostgresql.host` | string | `""` | Hostname of an external PostgreSQL server. Required when `database.backend` is `postgres` and `postgres.enabled` is `false`. |
| `externalPostgresql.port` | int | `5432` | Port of the external PostgreSQL server. |
| `externalPostgresql.database` | string | `""` | Name of the database used by kMLOps. It must already exist; kMLOps creates its tables at start-up. |
| `externalPostgresql.user` | string | `""` | PostgreSQL user. |
| `externalPostgresql.password` | string | `""` | PostgreSQL password. Stored in a Secret created by this chart. Ignored when `externalPostgresql.existingSecret` is set. |
| `externalPostgresql.existingSecret` | string | `""` | Name of an existing Secret containing the PostgreSQL password. Takes precedence over `externalPostgresql.password`. |
| `externalPostgresql.existingSecretPasswordKey` | string | `"password"` | Key of `externalPostgresql.existingSecret` holding the password. |
| `externalMlflow.trackingUri` | string | `""` | Tracking URI of an external MLflow server (e.g. `http://<host>:<port>`). Used only when `mlflow.enabled` is `false`. If empty and the bundled MLflow is disabled, kMLOps runs without MLflow and only tracks its own trainings. The server must accept artifact uploads from the training pods (proxied artifact storage, `--serve-artifacts`), because the training Jobs only receive the tracking URI. |
| `mlflow.enabled` | bool | `true` | Deploy the bundled MLflow server (`<release>-mlflow`, ertis/mlflow chart). kMLOps and the training Jobs use its in-cluster Service as tracking URI. If `false`, set `externalMlflow.trackingUri` (or leave it empty to run without MLflow). |
| `mlflow.artifacts.backend` | string | `"s3"` | Where MLflow stores the run artifacts and models. `s3` uses the object storage configured in `mlflow.artifacts.s3` (by default the bundled MinIO); `local` stores them on the MLflow volume (increase `mlflow.persistence.size` accordingly). |
| `mlflow.artifacts.s3.endpoint` | string | `"http://{{ .Release.Name }}-minio:9000"` | URL (with scheme) of the object storage used by MLflow, rendered with `tpl`. The default is the bundled MinIO; set it when `minio.enabled` is `false`. |
| `mlflow.artifacts.s3.bucket` | string | `"mlflow"` | Bucket where MLflow stores the artifacts. MLflow creates it at start-up if it does not exist. Keep it different from `bucketName`. |
| `mlflow.artifacts.s3.existingSecret` | string | `"{{ .Release.Name }}-minio"` | Existing Secret with the object storage credentials, rendered with `tpl`. The default is the Secret of the bundled MinIO. |
| `mlflow.artifacts.s3.accessKeyKey` | string | `"root-user"` | Key of the access key inside `mlflow.artifacts.s3.existingSecret`. |
| `mlflow.artifacts.s3.secretKeyKey` | string | `"root-password"` | Key of the secret key inside `mlflow.artifacts.s3.existingSecret`. |
| `minio.enabled` | bool | `true` | Deploy a MinIO server together with kMLOps. If `false`, configure `externalMinio`. |
| `minio.auth.rootUser` | string | `"admin"` | MinIO root user, used by kMLOps and MLflow as access key. |
| `minio.auth.rootPassword` | string | `""` | MinIO root password. Leave empty to generate a random one (kept across upgrades) in the `<release>-minio` Secret. |
| `postgres.enabled` | bool | `false` | Deploy a PostgreSQL server and use it as the kMLOps training store (overrides `database.backend`). Disabled by default: kMLOps uses SQLite. |
| `postgres.auth.username` | string | `"kmlops"` | PostgreSQL user created at initialization and used by kMLOps. A database with the same name is created too. |
| `postgres.auth.database` | string | `"kmlops"` | Name of the database used by kMLOps. |
| `postgres.auth.password` | string | `""` | Password of the user. Leave empty to generate a random one in the `<release>-postgres` Secret. |
