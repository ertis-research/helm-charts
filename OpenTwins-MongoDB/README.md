# OpenTwins-MongoDB

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![AppVersion: 4.4.6](https://img.shields.io/badge/AppVersion-4.4.6-informational?style=flat-square)

This chart deploys [MongoDB](https://github.com/mongodb/mongo), a document-oriented NoSQL database, at a version compatible with [Eclipse Ditto](https://github.com/eclipse-ditto/ditto). It is intended to be used together with [OpenTwins](https://github.com/ertis-research/opentwins), the digital twins platform, as the persistence backend required by Eclipse Ditto.

By default the chart installs the official `mongo` image at tag `4.4.6` (the chart `appVersion`), which is an older release than the one proposed upstream by Eclipse Ditto.

## What the chart creates

- A `Deployment` named `<release>-mongodb` running a single MongoDB container on port `27017`.
- A `Service` named `<release>-mongodb` exposing the MongoDB port.
- A `PersistentVolume` named `ot-pv-mongodb` (8Gi, `ReadWriteOnce`, reclaim policy `Retain`) backed by a `hostPath` directory on the node, pre-bound to the claim below.
- A `PersistentVolumeClaim` named `ot-pvc-mongodb` (8Gi, `ReadWriteOnce`), mounted at `/data/db` in the MongoDB container.
- A `StorageClass` named `sc-mongodb` (`kubernetes.io/no-provisioner`, reclaim policy `Retain`).

Notes about the storage resources:

- The names of the `PersistentVolume`, `PersistentVolumeClaim` and `StorageClass` are fixed and do not depend on the release name. `PersistentVolume` and `StorageClass` are cluster-scoped, so only one release of this chart can exist per cluster.
- The volume size and the `hostPath` directory are not configurable through values.
- Because `hostPath` is used, the data lives on the node where the pod is scheduled. This is suitable for single-node or development clusters.
- MongoDB is deployed without authentication (the credentials environment variables in the template are commented out).

## Prerequisites

- Kubernetes cluster.
- [Helm](https://helm.sh/) 3.

## Installation

Add the ERTIS Research Helm repository and update the local index:

```bash
helm repo add ertis https://ertis-research.github.io/helm-charts/
helm repo update
```

Install the chart (replace `<release>` and `<namespace>` with your own values):

```bash
helm upgrade --install <release> ertis/OpenTwins-MongoDB -n <namespace> --create-namespace
```

To override default values, use a custom values file with `-f` and/or individual values with `--set`:

```bash
helm upgrade --install <release> ertis/OpenTwins-MongoDB -n <namespace> --create-namespace \
  -f my-values.yaml \
  --set service.type=ClusterIP
```

## Uninstallation

```bash
helm uninstall <release> -n <namespace>
```

The `PersistentVolume` uses the `Retain` reclaim policy, so the data stored on the node is kept after uninstalling. Remove the data and the `PersistentVolume` manually if they are no longer needed.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| replicaCount | int | `1` | Number of MongoDB pod replicas. Only applied when `autoscaling.enabled` is `false`. Since MongoDB is deployed as a standalone instance sharing a single `ReadWriteOnce` volume, values greater than `1` are not recommended. |
| image.repository | string | `"mongo"` | Container image repository for MongoDB. |
| image.tag | string | `"4.4.6"` | Container image tag. If empty, the chart `appVersion` is used. |
| image.pullPolicy | string | `"Always"` | Image pull policy. Accepted values: `Always` (pull on every pod start), `IfNotPresent` (pull only if the image is not on the node), `Never` (never pull, the image must already exist on the node). |
| serviceAccount.create | bool | `true` | Intended to control the creation of a service account. Currently not used by the chart templates. |
| serviceAccount.annotations | object | `{}` | Intended annotations for the service account. Currently not used by the chart templates. |
| podAnnotations | object | `{}` | Intended annotations for the pods. Currently not used by the chart templates. |
| podSecurityContext | object | `{}` | Intended pod-level security context. Currently not used by the chart templates. |
| ingress.enabled | bool | `false` | Intended to enable an ingress. Currently not used by the chart templates. |
| resources | object | `{}` | Intended CPU/memory requests and limits for the MongoDB container. Currently not used by the chart templates. |
| autoscaling.enabled | bool | `false` | When `true`, the `replicas` field is omitted from the `Deployment`. No `HorizontalPodAutoscaler` is created by this chart, so an external autoscaler would be needed. |
| autoscaling.minReplicas | int | `1` | Intended minimum number of replicas. Currently not used by the chart templates. |
| autoscaling.maxReplicas | int | `100` | Intended maximum number of replicas. Currently not used by the chart templates. |
| autoscaling.targetCPUUtilizationPercentage | int | `80` | Intended target CPU utilization. Currently not used by the chart templates. |
| nodeSelector | object | `{}` | Intended node selector for pod scheduling. Currently not used by the chart templates. |
| tolerations | list | `[]` | Intended tolerations for pod scheduling. Currently not used by the chart templates. |
| affinity | object | `{}` | Intended affinity rules for pod scheduling. Currently not used by the chart templates. |
| service.type | string | `"LoadBalancer"` | Kubernetes service type. `ClusterIP` exposes MongoDB only inside the cluster; `NodePort` exposes it on a port of every node (requires `service.nodePort`); `LoadBalancer` requests an external load balancer from the cloud provider or the cluster. |
| service.port | int | `27017` | Port exposed by the service. |
| service.targetPort | int | `27017` | Container port the service forwards traffic to. The MongoDB container listens on `27017`. |

### Additional values read by the templates but not defined in values.yaml

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| service.nodePort | int | not set | Node port written into the service. The template always renders this field, so when it is not set the rendered manifest contains an empty `nodePort`. Provide a value in the cluster node port range (default `30000-32767`) when using `service.type=NodePort`. |
| nameOverride | string | not set | Overrides the chart name in the `OpenTwins-MongoDB.name` helper. Resource names of this chart are derived from the release name, so it has little practical effect. |
| fullnameOverride | string | not set | Overrides the full name in the `OpenTwins-MongoDB.fullname` helper. This helper is only used by the test pod. |
| serviceAccount.name | string | not set | Name used by the `OpenTwins-MongoDB.serviceAccountName` helper. Not used by any deployed resource. |

## Connecting to MongoDB

Inside the cluster, the service is reachable at `<release>-mongodb.<namespace>.svc` on port `service.port` (default `27017`). Configure OpenTwins (Eclipse Ditto) to use this address as its MongoDB connection URI.

## Source

- MongoDB: <https://github.com/mongodb/mongo>
- OpenTwins: <https://github.com/ertis-research/opentwins>
- Chart repository: <https://github.com/ertis-research/helm-charts>
