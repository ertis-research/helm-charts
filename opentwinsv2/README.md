<div align="center">
  <img src="https://github.com/ertis-research/opentwins/assets/48439828/74f974ba-3804-46de-9149-2c4fe7702e93" width="130" height="130" />

  <h3>OpenTwinsv2</h3>
  <h4>Official Helm Chart Repository</h4>

</br>
<a href='https://github.com/ertis-research/opentwins/tree/v2-development' target="_blank"><img alt='GitHub' src='https://img.shields.io/badge/github-100000?style=for-the-badge&logo=GitHub&logoColor=000000&labelColor=33d9b2&color=40407a'/></a>
</div>

</br>

> [!WARNING]
> **WORK IN PROGRESS**
> 
> **OpenTwins v2 is currently under active development and is NOT ready for production or general use.** 
>
> The backend services are still being stabilized, and **the front-end has not yet been implemented**. Deploying this chart today will give you the underlying infrastructure and services, but there is **no user interface** and the platform should be considered **work in progress**. If you need a stable release, please use **OpenTwins v1** instead.
>
> Contributions, testing, and feedback on the current v2 services are welcome, but expectations should be set accordingly.

---

## 📖 Overview

This Helm chart deploys the full stack for **OpenTwinsv2**, orchestrating all the components required to build, run, and monitor scalable composite digital twins.

## ⚙️ Prerequisites

Before you begin, ensure you have the following prerequisites installed and configured:

*   Kubernetes
*   Helm
*   Sufficient cluster resources to run multiple database and messaging services.

## 🚀 Installation

*Reminder: This chart is intended for development and testing purposes only.*

To install the chart with the release name `opentwinsv2-dev` into a dedicated namespace:

```bash
# 1. Add the ERTIS helm repository
helm repo add ertis https://ertis-research.github.io/helm-charts/
helm repo update

# 2. Install the chart
helm upgrade --install opentwinsv2-dev ertis/opentwinsv2 -n opentwinsv2 --wait --dependency-update
```

### Uninstallation

To completely remove the deployment and all its associated Kubernetes resources:

```bash
helm uninstall opentwinsv2-dev -n opentwinsv2
```
> [!NOTE]
> PVCs created by stateful applications are not deleted by Helm to prevent accidental data loss. You will need to delete these manually if you want a completely clean slate.

## 🛠️ Configuration

All configuration is managed through a `values.yaml` file following standard Helm conventions. The chart is highly modular, allowing you to:

- Enable or disable individual components using the `<dependency_name>.enabled` flag.
- Override any dependency's default configuration by declaring its top-level key in your custom `values.yaml`.

To deploy with your custom configuration:

```bash
helm upgrade --install opentwinsv2-dev ertis/opentwinsv2 -n opentwinsv2 -f values.yaml
```

> [!IMPORTANT]
> This chart does not document the full set of configurable values for each third-party dependency. For the complete and up-to-date list of configurable options (such as setting up custom passwords, resource limits, or persistence settings), please refer to **each dependency's official Helm chart documentation**, linked in the table below.
 
## 📦 Dependencies

This chart is a composite of several open-source subcharts. Components marked as **Essential** are required for the core platform to function properly, the rest are optional add-ons.
 
| Component | Chart | Version | Repository | Status |
|---|---|---|---|---|
| Grafana | `grafana` | ~13.2.2 | [Link](https://artifacthub.io/packages/helm/grafana-community/grafana/13.2.2) | Essential |
| Mosquitto (MQTT broker) | `app-template` (alias `mosquitto`) | ~5.1.0 | [Link](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/other/app-template) | Essential |
| Redpanda | `redpanda` | ~26.2.3 | [Link](https://artifacthub.io/packages/helm/redpanda-data/redpanda/26.2.3) | Essential |
| Dgraph | `dgraph` | ~24.1.4 | [Link](https://artifacthub.io/packages/helm/dgraph/dgraph/24.1.4) | Essential |
| Redis | `redis` | ~0.34.32 | [Link](https://artifacthub.io/packages/helm/cloudpirates-redis/redis/0.34.32) | Essential |
| TimescaleDB | `timescaledb` | ~0.13.10 | [Link](https://artifacthub.io/packages/helm/cloudpirates-timescaledb/timescaledb/0.13.10) | Essential |
| Dapr | `dapr` | ~1.18.4 | [Link](https://artifacthub.io/packages/helm/dapr/dapr/1.18.4) | Essential |
| Kafka UI | `kafka-ui` | ~1.6.5 | [Link](https://artifacthub.io/packages/helm/kafka-ui/kafka-ui/1.6.5) | Optional |
| Dapr Dashboard | `dapr-dashboard` | ~0.15.0 | [Link](https://artifacthub.io/packages/helm/dapr/dapr-dashboard/0.15.0) | Optional |
 
**Optional components:** `kafka-ui` and `dapr-dashboard` are observability UIs and are **not required** for the platform to run. Disable them via `kafka-ui.enabled: false` and `dapr-dashboard.enabled: false` if you don't need them.
 
For the full list of configurable values, defaults, and advanced options for any dependency, consult that dependency's own repository/documentation linked above. This README does not duplicate that information, as it can change independently of this chart.
 
## 📄 License

See the repository's main `LICENSE` file for licensing terms of OpenTwins itself. Each dependency listed above retains its own license, please review them individually before deploying to a production environment.

> **A note on Redpanda:** Its Community Edition operates under the **Business Source License (BSL)** (which is free and source-available, converting to Apache 2.0 after 4 years, but restricts offering it as a commercial managed streaming service to third parties). If these terms conflict with your use case, you can simply disable the Redpanda dependency (`redpanda.enabled: false`) and point OpenTwins to any other Kafka-compatible broker (e.g., Apache Kafka via Strimzi).
