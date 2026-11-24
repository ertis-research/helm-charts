# mosquitto

![Version: 0.3.1](https://img.shields.io/badge/Version-0.3.1-informational?style=flat-square) ![AppVersion: 1.6.10](https://img.shields.io/badge/AppVersion-1.6.10-informational?style=flat-square)

This chart deploys [Eclipse Mosquitto](https://github.com/eclipse-mosquitto/mosquitto) ([website](https://mosquitto.org/)), an open-source message broker that implements the MQTT protocol. MQTT is a lightweight publish/subscribe messaging protocol widely used in IoT scenarios, and Mosquitto is used to exchange messages between devices and applications.

## What the chart creates

- A `Deployment` running the Mosquitto broker. The container exposes port `1883` (MQTT), port `9001` (declared as the `websocket` port) and, when SSL is enabled, port `8883` (MQTT over TLS).
- A `Service` exposing those ports.
- A `ConfigMap` with the `mosquitto.conf` file generated from the values.
- When authentication is enabled, a `ConfigMap` named `<release>-mosquitto-passwd` with the users defined in the values.
- When SSL is enabled and certificate/key data is provided, `Secret` objects named `<release>-mosquitto-certfile` and `<release>-mosquitto-keyfile`.
- Optionally, a `ServiceAccount`.

How the configuration is applied: init containers copy the configuration, the password file and the certificates into an `emptyDir` volume mounted at `/mosquitto/`. Because that volume is ephemeral, the broker configuration is rebuilt every time the pod starts. No persistent storage is configured for broker data.

The generated `mosquitto.conf` sets a listener on port `1883`, enables logging to stdout, and sets `allow_anonymous false` when authentication is enabled (`true` otherwise). The WebSocket port `9001` is exposed by the container and the service, but the generated configuration does not define a listener for it.

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
helm upgrade --install <release> ertis/mosquitto -n <namespace> --create-namespace
```

To override default values, use a custom values file with `-f` and/or individual values with `--set`:

```bash
helm upgrade --install <release> ertis/mosquitto -n <namespace> --create-namespace \
  -f my-values.yaml \
  --set service.type=ClusterIP
```

The in-cluster address of the broker is `<fullname>.<namespace>.svc` on port `1883`, where `<fullname>` is `<release>` if the release name contains `mosquitto`, or `<release>-mosquitto` otherwise (unless `fullnameOverride` is set).

## Uninstallation

```bash
helm uninstall <release> -n <namespace>
```

## Security notes

### Authentication credentials

The default `configuration.authentication.passwd` entry in `values.yaml` (`username: user`, `password: password`) is only a **placeholder** so that the chart can be installed out of the box. It is publicly known and **must be overridden before any real deployment**, for example with a private values file that is not committed to version control:

```yaml
configuration:
  authentication:
    enabled: true
    passwd:
      - username: <your-username>
        password: <your-strong-password>
```

Passwords are written in plain text into a `ConfigMap`, and an init container hashes them with `mosquitto_passwd -U` into the password file used by the broker. Anyone with read access to the `ConfigMap` in the cluster can read the clear-text passwords, so restrict access to the namespace accordingly. Disabling authentication (`configuration.authentication.enabled=false`) makes the broker accept anonymous connections.

### SSL/TLS certificates

SSL is disabled by default. When `configuration.ssl.enabled` is `true`, the broker opens an additional listener on port `8883` and the service exposes it. The certificate and the private key are provided as values:

- `configuration.ssl.certfile.data`: PEM content of the certificate.
- `configuration.ssl.keyfile.data`: PEM content of the private key.

When `data` is set, the chart stores it in a `Secret` (`<release>-mosquitto-certfile` and `<release>-mosquitto-keyfile`), and an init container copies it to `/mosquitto/certs/default.pem` and `/mosquitto/certs/default.key`. Do not commit certificates or keys to version control; pass them at install time, for example:

```bash
helm upgrade --install <release> ertis/mosquitto -n <namespace> \
  --set configuration.ssl.enabled=true \
  --set-file configuration.ssl.certfile.data=<path-to-certificate> \
  --set-file configuration.ssl.keyfile.data=<path-to-private-key>
```

Both `data` values must be set when SSL is enabled; otherwise the pod will not start, because the corresponding secret volumes are not created.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| replicaCount | int | `1` | Number of broker pod replicas. Each replica is an independent broker; there is no clustering or shared state between them. |
| image.repository | string | `"eclipse-mosquitto"` | Container image repository for Mosquitto. |
| image.tag | string | `"2.0.14"` | Container image tag. It is evaluated as a template (`tpl`) and has no fallback, so it must not be empty. Note that the chart `appVersion` (`1.6.10`) is not used. |
| image.pullPolicy | string | `"Always"` | Image pull policy for the broker container. Accepted values: `Always` (pull on every pod start), `IfNotPresent` (pull only if the image is not on the node), `Never` (never pull, the image must already exist on the node). The init containers that use the same image always use `IfNotPresent`. |
| imagePullSecrets | list | `[]` | List of image pull secrets (for example `- name: my-registry-secret`) used to pull images from private registries. |
| nameOverride | string | `""` | Overrides the chart name used in resource names and selector labels. |
| fullnameOverride | string | `""` | Overrides the full name used for the generated resources. |
| serviceAccount.create | bool | `true` | When `true`, a `ServiceAccount` is created and used by the pod. When `false`, the account named by `serviceAccount.name`, or `default` if not set, is used. |
| serviceAccount.name | string | `nil` | Name of the service account to use. If not set and `serviceAccount.create` is `true`, a name is generated from the full name. |
| service.type | string | `"LoadBalancer"` | Kubernetes service type. `ClusterIP` exposes the broker only inside the cluster; `NodePort` exposes it on a port of every node; `LoadBalancer` requests an external load balancer from the cloud provider or the cluster. |
| configuration.authentication.enabled | bool | `true` | When `true`, anonymous access is disabled (`allow_anonymous false`), a password `ConfigMap` is created and a password file is generated from `passwd`. When `false`, anonymous clients are allowed. |
| configuration.authentication.path | string | not set (commented out) | Directory of the password file referenced in `mosquitto.conf`. Defaults to `/mosquitto/auth` when not set. The init container always creates the file at `/mosquitto/auth/passwd`, so changing this value is not recommended. |
| configuration.authentication.passwd | list | `[{username: user, password: password}]` | List of broker users, each with `username` and `password`. The defaults are placeholders and must be overridden (see Security notes). Setting this key replaces the whole list. |
| configuration.ssl.enabled | bool | `false` | When `true`, adds a TLS listener on port `8883`, exposes that port in the container and service, and runs an init container that installs the certificate and key. |
| configuration.ssl.certfile.path | string | `"/mosquitto/certs/"` | Directory of the certificate referenced in `mosquitto.conf`. It is concatenated directly with `file`, so it must end with `/`. The init container always installs the certificate at `/mosquitto/certs/default.pem`. |
| configuration.ssl.certfile.file | string | `"default.pem"` | File name of the certificate referenced in `mosquitto.conf` (falls back to `default.pem` if empty). Keep the default, because the init container always creates `default.pem`. |
| configuration.ssl.certfile.data | string | not set (commented out) | PEM content of the certificate. When set together with `ssl.enabled`, a `Secret` is created and mounted into the init container. Required when SSL is enabled. |
| configuration.ssl.keyfile.path | string | `"/mosquitto/certs/"` | Directory of the private key referenced in `mosquitto.conf`. It is concatenated directly with `file`, so it must end with `/`. The init container always installs the key at `/mosquitto/certs/default.key`. |
| configuration.ssl.keyfile.file | string | `"default.key"` | File name of the private key referenced in `mosquitto.conf` (falls back to `default.key` if empty). Keep the default, because the init container always creates `default.key`. |
| configuration.ssl.keyfile.data | string | not set (commented out) | PEM content of the private key. When set together with `ssl.enabled`, a `Secret` is created and mounted into the init container. Required when SSL is enabled. |
| podSecurityContext | object | `nil` | Pod-level security context (for example `fsGroup`). The default is empty (null). |
| securityContext | object | `{}` | Security context of the broker container (for example `runAsNonRoot`, `runAsUser`, `capabilities`). Init containers do not use it. |
| resources | object | `{}` | CPU/memory requests and limits for the broker container. |
| nodeSelector | object | `{}` | Node selector for pod scheduling. |
| tolerations | list | `[]` | Tolerations for pod scheduling. |
| affinity | object | `{}` | Affinity rules for pod scheduling. |

### Additional values read by the templates but not defined in values.yaml

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| service.nodePort | int | not set (commented out) | Fixed node port applied to the MQTT port (`1883`) of the service. Only meaningful when `service.type` is `NodePort` (or `LoadBalancer` on clusters that allocate node ports). |
| service.annotations | object | not set | Annotations added to the service (for example to configure a cloud load balancer). |
| service.externalTrafficPolicy | string | not set | Sets `externalTrafficPolicy` on the service. `Cluster` routes external traffic to any node and may hide the client source IP; `Local` routes only to node-local pods and preserves the client source IP. |
| service.externalIPs | list | not set | List of external IPs for which the cluster should accept traffic to the service. |
| service.loadBalancerIP | string | not set | Requests a specific load balancer IP (when supported by the provider). The template also writes it into the service `status` block. |
| service.port | int | not set | Only referenced by the Helm test pod. The service itself always exposes port `1883`. |

## Source

- Eclipse Mosquitto: <https://github.com/eclipse-mosquitto/mosquitto>
- Website: <https://mosquitto.org/>
- Chart repository: <https://github.com/ertis-research/helm-charts>
