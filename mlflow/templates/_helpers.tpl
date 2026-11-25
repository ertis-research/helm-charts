{{/*
Expand the name of the chart.
*/}}
{{- define "mlflow.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mlflow.fullname" -}}
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
{{- define "mlflow.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mlflow.labels" -}}
helm.sh/chart: {{ include "mlflow.chart" . }}
{{ include "mlflow.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/component: tracking-server
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mlflow.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mlflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Container image of MLflow. Defaults to the official full image of the chart appVersion.
*/}}
{{- define "mlflow.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default (printf "v%s-full" .Chart.AppVersion)) }}
{{- end }}

{{/*
Name of the PVC holding the SQLite database (and the local artifacts).
*/}}
{{- define "mlflow.claimName" -}}
{{- if .Values.persistence.existingClaim -}}
{{- tpl .Values.persistence.existingClaim . -}}
{{- else -}}
{{- printf "%s-data" (include "mlflow.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{/*
Name of the bundled MinIO resources. It mirrors the "cloudpirates.fullname" helper used by the
MinIO subchart (release-based, honouring its nameOverride/fullnameOverride values).
*/}}
{{- define "mlflow.minio.fullname" -}}
{{- $values := .Values.minio | default dict -}}
{{- if $values.fullnameOverride -}}
{{- $values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default "minio" $values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Effective artifact backend: "s3" when the bundled MinIO is enabled, otherwise artifacts.backend.
*/}}
{{- define "mlflow.artifactsBackend" -}}
{{- if .Values.minio.enabled -}}
s3
{{- else -}}
{{- .Values.artifacts.backend -}}
{{- end -}}
{{- end }}

{{/*
S3 endpoint URL: the bundled MinIO when it is enabled, otherwise artifacts.s3.endpoint (required, see mlflow.validate).
*/}}
{{- define "mlflow.s3.endpoint" -}}
{{- if .Values.minio.enabled -}}
{{- printf "http://%s:%v" (include "mlflow.minio.fullname" .) (dig "service" "port" 9000 .Values.minio) -}}
{{- else -}}
{{- tpl .Values.artifacts.s3.endpoint . -}}
{{- end -}}
{{- end }}

{{/*
Whether the chart creates the Secret with the S3 credentials ("true" or empty).
*/}}
{{- define "mlflow.s3.createSecret" -}}
{{- $s3 := .Values.artifacts.s3 -}}
{{- if and (not .Values.minio.enabled) (eq .Values.artifacts.backend "s3") (not $s3.existingSecret) $s3.accessKey $s3.secretKey -}}
true
{{- end -}}
{{- end }}

{{/*
Name of the Secret with the S3 credentials (empty when no credentials are configured).
With the bundled MinIO it is the MinIO credentials Secret.
*/}}
{{- define "mlflow.s3.secretName" -}}
{{- if .Values.minio.enabled -}}
{{- with dig "auth" "existingSecret" "" .Values.minio -}}
{{- tpl . $ -}}
{{- else -}}
{{- include "mlflow.minio.fullname" . -}}
{{- end -}}
{{- else if .Values.artifacts.s3.existingSecret -}}
{{- tpl .Values.artifacts.s3.existingSecret . -}}
{{- else if include "mlflow.s3.createSecret" . -}}
{{- printf "%s-s3" (include "mlflow.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{/*
Keys of the access key and secret key inside the credentials Secret.
*/}}
{{- define "mlflow.s3.accessKeyKey" -}}
{{- if .Values.minio.enabled -}}
{{- if dig "auth" "existingSecret" "" .Values.minio -}}
{{- dig "auth" "existingSecretUserKey" "user" .Values.minio -}}
{{- else -}}
root-user
{{- end -}}
{{- else -}}
{{- .Values.artifacts.s3.accessKeyKey -}}
{{- end -}}
{{- end }}

{{- define "mlflow.s3.secretKeyKey" -}}
{{- if .Values.minio.enabled -}}
{{- if dig "auth" "existingSecret" "" .Values.minio -}}
{{- dig "auth" "existingSecretPasswordKey" "password" .Values.minio -}}
{{- else -}}
root-password
{{- end -}}
{{- else -}}
{{- .Values.artifacts.s3.secretKeyKey -}}
{{- end -}}
{{- end }}

{{/*
S3 environment variables shared by the MLflow server and the bucket initialization container.
AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY are the standard variable names read by the S3 client library (boto3)
for any S3-compatible object storage, including MinIO; they do not imply Amazon Web Services.
*/}}
{{- define "mlflow.s3.env" -}}
{{- $secretName := include "mlflow.s3.secretName" . -}}
- name: MLFLOW_S3_ENDPOINT_URL
  value: {{ include "mlflow.s3.endpoint" . | quote }}
- name: MLFLOW_ARTIFACTS_BUCKET
  value: {{ .Values.artifacts.s3.bucket | quote }}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: {{ include "mlflow.s3.accessKeyKey" . }}
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $secretName }}
      key: {{ include "mlflow.s3.secretKeyKey" . }}
{{- end }}

{{/*
Hosts accepted by MLflow (MLFLOW_SERVER_ALLOWED_HOSTS): the in-cluster Service names, localhost,
the Ingress hosts, the HTTPRoute hostnames and extraAllowedHosts.
*/}}
{{- define "mlflow.allowedHosts" -}}
{{- $fullName := include "mlflow.fullname" . -}}
{{- $ns := .Release.Namespace -}}
{{- $hosts := list -}}
{{- range $base := list $fullName (printf "%s.%s" $fullName $ns) (printf "%s.%s.svc" $fullName $ns) "localhost" -}}
{{- $hosts = append $hosts $base -}}
{{- $hosts = append $hosts (printf "%s:*" $base) -}}
{{- end -}}
{{- if .Values.ingress.enabled -}}
{{- range .Values.ingress.hosts -}}
{{- $hosts = append $hosts .host -}}
{{- end -}}
{{- end -}}
{{- if .Values.httpRoute.enabled -}}
{{- $hosts = concat $hosts .Values.httpRoute.hostnames -}}
{{- end -}}
{{- range .Values.extraAllowedHosts -}}
{{- $hosts = append $hosts (tpl . $) -}}
{{- end -}}
{{- $hosts | compact | uniq | join "," -}}
{{- end }}

{{/*
Validate the configuration.
*/}}
{{- define "mlflow.validate" -}}
{{- if not (has .Values.artifacts.backend (list "local" "s3")) -}}
{{- fail (printf "artifacts.backend must be 'local' or 's3', got '%s'" .Values.artifacts.backend) -}}
{{- end -}}
{{- if and .Values.minio.enabled (eq (include "mlflow.minio.fullname" .) (include "mlflow.fullname" .)) -}}
{{- fail (printf "The release name '%s' makes the bundled MinIO resources collide with the MLflow resources; use another release name or set minio.nameOverride" .Release.Name) -}}
{{- end -}}
{{- if eq (include "mlflow.artifactsBackend" .) "s3" -}}
{{- if not .Values.artifacts.s3.bucket -}}
{{- fail "artifacts.s3.bucket is required when artifacts.backend is 's3'" -}}
{{- end -}}
{{- $s3 := .Values.artifacts.s3 -}}
{{- if not .Values.minio.enabled -}}
{{- if not $s3.endpoint -}}
{{- fail "artifacts.s3.endpoint is required when artifacts.backend is 's3' and minio.enabled is false (URL of the external object storage, e.g. http://<host>:9000)" -}}
{{- end -}}
{{- if and (not $s3.existingSecret) (not (and $s3.accessKey $s3.secretKey)) -}}
{{- fail "artifacts.s3.existingSecret, or both artifacts.s3.accessKey and artifacts.s3.secretKey, are required when artifacts.backend is 's3' and minio.enabled is false" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
