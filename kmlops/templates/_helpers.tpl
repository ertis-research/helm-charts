{{/*
Expand the name of the chart.
*/}}
{{- define "kmlops.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kmlops.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kmlops.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kmlops.labels" -}}
helm.sh/chart: {{ include "kmlops.chart" . }}
{{ include "kmlops.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kmlops.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kmlops.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "kmlops.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "kmlops.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container image of the kMLOps API.
*/}}
{{- define "kmlops.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Name of the Secret created by this chart for external MinIO and PostgreSQL credentials.
*/}}
{{- define "kmlops.secretName" -}}
{{- printf "%s-credentials" (include "kmlops.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Training store backend: "postgres" when the bundled PostgreSQL is enabled, otherwise database.backend.
*/}}
{{- define "kmlops.databaseBackend" -}}
{{- if .Values.postgres.enabled -}}
postgres
{{- else -}}
{{- .Values.database.backend -}}
{{- end -}}
{{- end }}

{{/*
Name of the PVC holding the SQLite training store.
*/}}
{{- define "kmlops.dataClaimName" -}}
{{- .Values.persistence.existingClaim | default (printf "%s-data" (include "kmlops.fullname" .)) }}
{{- end }}

{{/*
Names of the bundled subchart resources. They mirror the "cloudpirates.fullname" helper used by the
MinIO and PostgreSQL subcharts (release-based, honouring their nameOverride/fullnameOverride values).
Usage: {{ include "kmlops.subchartFullname" (dict "name" "minio" "values" .Values.minio "context" .) }}
*/}}
{{- define "kmlops.subchartFullname" -}}
{{- $values := .values | default dict -}}
{{- if $values.fullnameOverride -}}
{{- $values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .name $values.nameOverride -}}
{{- if contains $name .context.Release.Name -}}
{{- .context.Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .context.Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "kmlops.minio.fullname" -}}
{{- include "kmlops.subchartFullname" (dict "name" "minio" "values" .Values.minio "context" .) -}}
{{- end }}

{{- define "kmlops.postgres.fullname" -}}
{{- include "kmlops.subchartFullname" (dict "name" "postgres" "values" .Values.postgres "context" .) -}}
{{- end }}

{{/*
Name of the bundled MLflow resources (ertis/mlflow subchart, same naming rule as the other subcharts).
*/}}
{{- define "kmlops.mlflow.fullname" -}}
{{- include "kmlops.subchartFullname" (dict "name" "mlflow" "values" .Values.mlflow "context" .) -}}
{{- end }}

{{/*
Default S3 settings of the bundled MLflow in values.yaml. They point to the bundled MinIO and are used
to detect configurations where they no longer match it (see kmlops.validate).
*/}}
{{- define "kmlops.mlflow.defaultS3Endpoint" -}}
http://{{ "{{" }} .Release.Name {{ "}}" }}-minio:9000
{{- end }}

{{- define "kmlops.mlflow.defaultS3Secret" -}}
{{ "{{" }} .Release.Name {{ "}}" }}-minio
{{- end }}

{{/*
MinIO endpoint (host:port, without scheme).
*/}}
{{- define "kmlops.minio.endpoint" -}}
{{- if .Values.minio.enabled -}}
{{- printf "%s:%v" (include "kmlops.minio.fullname" .) (dig "service" "port" 9000 .Values.minio) -}}
{{- else -}}
{{- required "externalMinio.endpoint is required when minio.enabled is false" .Values.externalMinio.endpoint -}}
{{- end -}}
{{- end }}

{{/*
Whether kMLOps connects to MinIO over HTTPS.
*/}}
{{- define "kmlops.minio.secure" -}}
{{- if .Values.minio.enabled -}}
false
{{- else -}}
{{- .Values.externalMinio.secure | toString -}}
{{- end -}}
{{- end }}

{{/*
Secret name and keys holding the MinIO access and secret keys.
*/}}
{{- define "kmlops.minio.secretName" -}}
{{- if .Values.minio.enabled -}}
{{- dig "auth" "existingSecret" "" .Values.minio | default (include "kmlops.minio.fullname" .) -}}
{{- else if .Values.externalMinio.existingSecret -}}
{{- .Values.externalMinio.existingSecret -}}
{{- else -}}
{{- include "kmlops.secretName" . -}}
{{- end -}}
{{- end }}

{{- define "kmlops.minio.accessKeyKey" -}}
{{- if .Values.minio.enabled -}}
{{- if dig "auth" "existingSecret" "" .Values.minio -}}
{{- dig "auth" "existingSecretUserKey" "user" .Values.minio -}}
{{- else -}}
root-user
{{- end -}}
{{- else if .Values.externalMinio.existingSecret -}}
{{- .Values.externalMinio.existingSecretAccessKeyKey -}}
{{- else -}}
minio-access-key
{{- end -}}
{{- end }}

{{- define "kmlops.minio.secretKeyKey" -}}
{{- if .Values.minio.enabled -}}
{{- if dig "auth" "existingSecret" "" .Values.minio -}}
{{- dig "auth" "existingSecretPasswordKey" "password" .Values.minio -}}
{{- else -}}
root-password
{{- end -}}
{{- else if .Values.externalMinio.existingSecret -}}
{{- .Values.externalMinio.existingSecretSecretKeyKey -}}
{{- else -}}
minio-secret-key
{{- end -}}
{{- end }}

{{/*
Whether this chart must create its own credentials Secret.
*/}}
{{- define "kmlops.createSecret" -}}
{{- $minio := and (not .Values.minio.enabled) (not .Values.externalMinio.existingSecret) -}}
{{- $postgres := and (eq (include "kmlops.databaseBackend" .) "postgres") (not .Values.postgres.enabled) (not .Values.externalPostgresql.existingSecret) -}}
{{- if or $minio $postgres -}}true{{- end -}}
{{- end }}

{{/*
PostgreSQL connection settings.
*/}}
{{- define "kmlops.postgres.host" -}}
{{- if .Values.postgres.enabled -}}
{{- include "kmlops.postgres.fullname" . -}}
{{- else -}}
{{- required "externalPostgresql.host is required when database.backend is postgres and postgres.enabled is false" .Values.externalPostgresql.host -}}
{{- end -}}
{{- end }}

{{- define "kmlops.postgres.port" -}}
{{- if .Values.postgres.enabled -}}
{{- dig "service" "port" 5432 .Values.postgres -}}
{{- else -}}
{{- .Values.externalPostgresql.port -}}
{{- end -}}
{{- end }}

{{- define "kmlops.postgres.user" -}}
{{- if .Values.postgres.enabled -}}
{{- dig "auth" "username" "" .Values.postgres | default "postgres" -}}
{{- else -}}
{{- required "externalPostgresql.user is required when database.backend is postgres and postgres.enabled is false" .Values.externalPostgresql.user -}}
{{- end -}}
{{- end }}

{{- define "kmlops.postgres.database" -}}
{{- if .Values.postgres.enabled -}}
{{- dig "auth" "database" "" .Values.postgres | default (include "kmlops.postgres.user" .) -}}
{{- else -}}
{{- required "externalPostgresql.database is required when database.backend is postgres and postgres.enabled is false" .Values.externalPostgresql.database -}}
{{- end -}}
{{- end }}

{{- define "kmlops.postgres.secretName" -}}
{{- if .Values.postgres.enabled -}}
{{- dig "auth" "existingSecret" "" .Values.postgres | default (include "kmlops.postgres.fullname" .) -}}
{{- else if .Values.externalPostgresql.existingSecret -}}
{{- .Values.externalPostgresql.existingSecret -}}
{{- else -}}
{{- include "kmlops.secretName" . -}}
{{- end -}}
{{- end }}

{{- define "kmlops.postgres.passwordKey" -}}
{{- if .Values.postgres.enabled -}}
{{- if dig "auth" "existingSecret" "" .Values.postgres -}}
{{- dig "auth" "secretKeys" "adminPasswordKey" "postgres-password" .Values.postgres -}}
{{- else -}}
postgres-password
{{- end -}}
{{- else if .Values.externalPostgresql.existingSecret -}}
{{- .Values.externalPostgresql.existingSecretPasswordKey -}}
{{- else -}}
postgres-password
{{- end -}}
{{- end }}

{{/*
MLflow tracking URI (empty when MLflow is not used).
*/}}
{{- define "kmlops.mlflow.trackingUri" -}}
{{- if .Values.mlflow.enabled -}}
{{- printf "http://%s:%v" (include "kmlops.mlflow.fullname" .) (dig "service" "port" 5000 .Values.mlflow) -}}
{{- else -}}
{{- .Values.externalMlflow.trackingUri -}}
{{- end -}}
{{- end }}

{{/*
Validate the configuration.
*/}}
{{- define "kmlops.validate" -}}
{{- $backend := include "kmlops.databaseBackend" . -}}
{{- if not (has $backend (list "sqlite" "postgres")) -}}
{{- fail (printf "database.backend must be 'sqlite' or 'postgres', got '%s'" $backend) -}}
{{- end -}}
{{- if and (eq $backend "sqlite") (gt (int .Values.replicaCount) 1) -}}
{{- fail "replicaCount must be 1 when the training store is SQLite; use database.backend=postgres (or postgres.enabled=true) to run more replicas" -}}
{{- end -}}
{{- if and (not .Values.minio.enabled) (not .Values.externalMinio.existingSecret) (or (not .Values.externalMinio.accessKey) (not .Values.externalMinio.secretKey)) -}}
{{- fail "externalMinio.accessKey and externalMinio.secretKey (or externalMinio.existingSecret) are required when minio.enabled is false" -}}
{{- end -}}
{{- $apiName := include "kmlops.fullname" . -}}
{{- if or (and .Values.minio.enabled (eq (include "kmlops.minio.fullname" .) $apiName)) (and .Values.postgres.enabled (eq (include "kmlops.postgres.fullname" .) $apiName)) -}}
{{- fail (printf "The release name '%s' makes the bundled MinIO/PostgreSQL resources collide with the kMLOps resources; use another release name or set minio.nameOverride/postgres.nameOverride" .Release.Name) -}}
{{- end -}}
{{- if and (eq $backend "postgres") (not .Values.postgres.enabled) (not .Values.externalPostgresql.existingSecret) (not .Values.externalPostgresql.password) -}}
{{- fail "externalPostgresql.password (or externalPostgresql.existingSecret) is required when database.backend is postgres and postgres.enabled is false" -}}
{{- end -}}
{{- if .Values.mlflow.enabled -}}
{{- include "kmlops.validateMlflow" . -}}
{{- end -}}
{{- end }}

{{/*
Validate the bundled MLflow (ertis/mlflow subchart). The subchart cannot read the kMLOps values, so its
artifact storage is configured in mlflow.artifacts.s3; by default it points to the bundled MinIO. These
checks catch configurations where those defaults no longer match the MinIO actually used by kMLOps.
*/}}
{{- define "kmlops.validateMlflow" -}}
{{- $mlflowName := include "kmlops.mlflow.fullname" . -}}
{{- $names := list (include "kmlops.fullname" .) -}}
{{- if .Values.minio.enabled }}{{ $names = append $names (include "kmlops.minio.fullname" .) }}{{ end -}}
{{- if .Values.postgres.enabled }}{{ $names = append $names (include "kmlops.postgres.fullname" .) }}{{ end -}}
{{- if has $mlflowName $names -}}
{{- fail (printf "The release name '%s' makes the bundled MLflow resources collide with other resources of the release; use another release name or set mlflow.nameOverride" .Release.Name) -}}
{{- end -}}
{{- $backend := dig "artifacts" "backend" "local" .Values.mlflow -}}
{{- $s3 := dig "artifacts" "s3" dict .Values.mlflow -}}
{{- if and (eq $backend "s3") (not (dig "minio" "enabled" false .Values.mlflow)) -}}
{{- $endpoint := $s3.endpoint | default "" -}}
{{- $secret := $s3.existingSecret | default "" -}}
{{- $defaultEndpoint := eq $endpoint (include "kmlops.mlflow.defaultS3Endpoint" .) -}}
{{- $defaultSecret := eq $secret (include "kmlops.mlflow.defaultS3Secret" .) -}}
{{- if not .Values.minio.enabled -}}
{{- if or $defaultEndpoint $defaultSecret -}}
{{- fail "minio.enabled is false, but mlflow.artifacts.s3 still points to the bundled MinIO. Set mlflow.artifacts.s3.endpoint (URL with scheme) and mlflow.artifacts.s3.existingSecret with accessKeyKey/secretKeyKey (or accessKey/secretKey) for the external object storage, or set mlflow.artifacts.backend=local" -}}
{{- end -}}
{{- else -}}
{{- $expectedEndpoint := printf "http://%s" (include "kmlops.minio.endpoint" .) -}}
{{- if and $defaultEndpoint (ne (tpl $endpoint .) $expectedEndpoint) -}}
{{- fail (printf "The default mlflow.artifacts.s3.endpoint does not match the bundled MinIO endpoint '%s' (release name, minio.nameOverride or minio.service.port changed); set mlflow.artifacts.s3.endpoint explicitly" $expectedEndpoint) -}}
{{- end -}}
{{- if and $defaultSecret (or (ne (tpl $secret .) (include "kmlops.minio.secretName" .)) (ne ($s3.accessKeyKey | default "") (include "kmlops.minio.accessKeyKey" .)) (ne ($s3.secretKeyKey | default "") (include "kmlops.minio.secretKeyKey" .))) -}}
{{- fail (printf "The default mlflow.artifacts.s3 credentials do not match the bundled MinIO Secret '%s' (keys '%s'/'%s'); set mlflow.artifacts.s3.existingSecret, accessKeyKey and secretKeyKey explicitly" (include "kmlops.minio.secretName" .) (include "kmlops.minio.accessKeyKey" .) (include "kmlops.minio.secretKeyKey" .)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
