# mqtttomongo

![Version: 1.0.1](https://img.shields.io/badge/Version-1.0.1-informational?style=flat-square) ![AppVersion: latest](https://img.shields.io/badge/AppVersion-latest-informational?style=flat-square)

This chart deploys [MqttToMongo](https://github.com/ertis-research/mqtttomongo), an application developed by ERTIS Research that subscribes to an MQTT broker and stores the received messages in a MongoDB database.

## What the chart creates

- A `Deployment` named `<release>-mqtt-mongo` running the `ertis/mqtttomongo` image. The container listens on port `8001`.
- A `Service` named `mqtt-mongo` (fixed name, independent of the release name).
- Optionally, a `ServiceAccount`.

## How it connects to MQTT and MongoDB

The chart configures the application only through two environment variables:

| Environment variable | Value | Meaning |
|----------------------|-------|---------|
| `MOSQUITTO_BROKER` | The Helm release name | Host name of the MQTT broker. The chart assumes that a service with the same name as the release exists in the same namespace. |
| `MQTTPORT` | `mqttport` | Port of the MQTT broker. |

No environment variable or value is defined for the MongoDB connection, so this chart does not configure it. Refer to the [MqttToMongo repository](https://github.com/ertis-research/mqtttomongo) for how the application locates its MongoDB database.

Because the broker host is the release name, the release must be named so that it resolves to the broker service, or the broker service must be otherwise reachable under that name. For example, the [mosquitto chart](../mosquitto) names its service `<release>` only when the release name contains `mosquitto`; otherwise the service is named `<release>-mosquitto`.

## Prerequisites

- Kubernetes cluster.
- [Helm](https://helm.sh/) 3.
- A reachable MQTT broker (for example, the `ertis/mosquitto` chart) and a MongoDB database (for example, the `ertis/OpenTwins-MongoDB` chart).

## Installation

Add the ERTIS Research Helm repository and update the local index:

```bash
helm repo add ertis https://ertis-research.github.io/helm-charts/
helm repo update
```

Install the chart (replace `<release>` and `<namespace>` with your own values):

```bash
helm upgrade --install <release> ertis/mqtttomongo -n <namespace> --create-namespace
```

To override default values, use a custom values file with `-f` and/or individual values with `--set`:

```bash
helm upgrade --install <release> ertis/mqtttomongo -n <namespace> --create-namespace \
  -f my-values.yaml \
  --set mqttport=1883
```

## Uninstallation

```bash
helm uninstall <release> -n <namespace>
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| replicaCount | int | `1` | Number of application pod replicas. Only applied when `autoscaling.enabled` is `false`. |
| mqttport | int | `30510` | Port of the MQTT broker, passed to the container as `MQTTPORT`. Set it to the port on which your broker is reachable (for example `1883` for the default MQTT port of the `ertis/mosquitto` chart). |
| image.repository | string | `"ertis/mqtttomongo"` | Container image repository. |
| image.tag | string | not set | Container image tag. When not set, the chart `appVersion` (`latest`) is used. |
| image.pullPolicy | string | `"Always"` | Image pull policy. Accepted values: `Always` (pull on every pod start), `IfNotPresent` (pull only if the image is not on the node), `Never` (never pull, the image must already exist on the node). |
| serviceAccount.create | bool | `true` | When `true`, a `ServiceAccount` is created. The deployment does not reference it, so pods use the `default` service account. |
| serviceAccount.annotations | object | `{}` | Annotations added to the created `ServiceAccount`. |
| serviceAccount.name | string | not set | Name of the service account. Only used for the generated `ServiceAccount` resource. |
| podAnnotations | object | `{}` | Intended annotations for the pods. Currently not used by the chart templates. |
| podSecurityContext | object | `{}` | Intended pod-level security context. Currently not used by the chart templates. |
| service.type | string | `"NodePort"` | Kubernetes service type. `ClusterIP` exposes the service only inside the cluster; `NodePort` exposes it on `service.nodePort` of every node; `LoadBalancer` requests an external load balancer from the cloud provider or the cluster. |
| service.nodePort | int | `31187` | Node port assigned to the service. The template always renders this field, so it is meaningful for `NodePort` (and `LoadBalancer` on clusters that allocate node ports) and must be within the cluster node port range (default `30000-32767`). For `ClusterIP` it must be unset or the installation will fail. |
| service.port | int | `7998` | Port exposed by the service. |
| service.targetPort | int | `8001` | Container port the service forwards traffic to. The application container listens on `8001`. |
| ingress.enabled | bool | `false` | Intended to enable an ingress. Currently not used by the chart templates. |
| resources | object | `{}` | Intended CPU/memory requests and limits for the container. Currently not used by the chart templates. |
| autoscaling.enabled | bool | `false` | When `true`, the `replicas` field is omitted from the `Deployment`. No `HorizontalPodAutoscaler` is created by this chart, so an external autoscaler would be needed. |
| autoscaling.minReplicas | int | `1` | Intended minimum number of replicas. Currently not used by the chart templates. |
| autoscaling.maxReplicas | int | `100` | Intended maximum number of replicas. Currently not used by the chart templates. |
| autoscaling.targetCPUUtilizationPercentage | int | `80` | Intended target CPU utilization. Currently not used by the chart templates. |
| nodeSelector | object | `{}` | Intended node selector for pod scheduling. Currently not used by the chart templates. |
| tolerations | list | `[]` | Intended tolerations for pod scheduling. Currently not used by the chart templates. |
| affinity | object | `{}` | Intended affinity rules for pod scheduling. Currently not used by the chart templates. |

## Source

- MqttToMongo: <https://github.com/ertis-research/mqtttomongo>
- Chart repository: <https://github.com/ertis-research/helm-charts>
