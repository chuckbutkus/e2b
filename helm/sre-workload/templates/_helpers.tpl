{{/*
Expand the name of the chart.
*/}}
{{- define "sre-workload.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "sre-workload.fullname" -}}
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
Common labels
*/}}
{{- define "sre-workload.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "sre-workload.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "sre-workload.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sre-workload.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name to use
*/}}
{{- define "sre-workload.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "sre-workload.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Shared probe spec builder — renders http/tcp/exec depending on
.Values.probes.type, so switching probe mechanism (e.g. once the real image
is inspected) is a one-line values change instead of editing three probe
blocks in the Deployment. Call with:
  (dict "probe" .Values.probes.<startup|readiness|liveness> "root" . "path" <path>)
*/}}
{{- define "sre-workload.probeSpec" -}}
{{- $root := .root -}}
{{- $probe := .probe -}}
{{- $path := .path -}}
{{- if eq $root.Values.probes.type "http" }}
httpGet:
  path: {{ $path }}
  port: http
{{- else if eq $root.Values.probes.type "tcp" }}
tcpSocket:
  port: http
{{- else }}
exec:
  command: ["/bin/sh", "-c", "exit 0"] # TODO: replace with real exec check
{{- end }}
{{- with $probe.initialDelaySeconds }}
initialDelaySeconds: {{ . }}
{{- end }}
periodSeconds: {{ $probe.periodSeconds }}
{{- with $probe.timeoutSeconds }}
timeoutSeconds: {{ . }}
{{- end }}
failureThreshold: {{ $probe.failureThreshold }}
{{- end }}
