# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Repository overview

This is the Helm chart repository of the **ERTIS Research** group (University of Málaga). Each top-level directory containing a `Chart.yaml` is an independent chart. Charts are published automatically to `https://ertis-research.github.io/helm-charts/` by [.github/workflows/release.yml](.github/workflows/release.yml) (`helm/chart-releaser-action`) on every push to `main`.

Current layout:

| Directory | Notes |
|-----------|-------|
| `OpenTwins/` | OpenTwins v1 platform (legacy layout: `apiVersion: v1`, `requirements.yaml`/`requirements.lock`) |
| `OpenTwins-Lightweight/` | Lightweight variant of OpenTwins v1 |
| `OpenTwins-MongoDB/` | MongoDB version compatible with Eclipse Ditto |
| `mosquitto/` | Eclipse Mosquitto MQTT broker |
| `mqtttomongo/` | MQTT-to-MongoDB bridge |
| `opentwinsv2/` | OpenTwins v2 (`apiVersion: v2`, `Chart.lock`, umbrella chart with many dependencies) |
| `tests/` | Values files used for manual testing installs |

Dependency archives (`<chart>/charts/*.tgz`) and lock files are committed to the repository.

## Hard rules

These rules are mandatory. Some existing charts do not comply yet; that does **not** relax the rules for new work.

### 1. Git: never commit, never branch
- **Never** run `git commit`, `git push`, `git checkout -b`, `git branch`, `git switch -c`, `git stash`, `git rebase`, `git merge` or any other command that creates commits or branches or rewrites history.
- When a change is finished, give the user a ready-to-use commit message in English following [Conventional Commits](https://www.conventionalcommits.org/) (e.g. `feat(opentwinsv2): add configurable resources for events service`). The user commits personally.
- Read-only git commands (`git status`, `git diff`, `git log`, `git show`) are allowed.

### 2. Do not modify existing charts unless explicitly asked
- Do not edit, rename, reformat or "clean up" an existing chart unless the user explicitly requests a change to that chart.
- If you notice a problem in an existing chart (rule violation, bug, outdated dependency), report it to the user instead of fixing it.

### 3. Chart names are always lowercase
- New chart names (`name:` in `Chart.yaml`) and their directory names must be lowercase, using hyphens as separators (e.g. `opentwins-mongodb`, not `OpenTwins-MongoDB`).
- Some legacy charts use uppercase names; do not rename them unless the user asks (renaming changes the published chart name and breaks existing users).

### 4. No IPs, URLs or sensitive information in charts
- Never hardcode IP addresses, hostnames, internal endpoints, URLs, credentials, tokens, passwords, certificates, keys or any other sensitive data in templates, Jobs, post-install hooks, scripts, ConfigMaps, Secrets or any other chart file.
- Anything environment-specific must be exposed as a value. Defaults must be empty or generic, and in-cluster addresses must be built from Helm context (e.g. `{{ include "<chart>.fullname" . }}`, `{{ .Release.Name }}`, `{{ .Release.Namespace }}`), never written literally.
- Secrets must be supplied through values or references to existing Kubernetes Secrets (`existingSecret` pattern), never committed with real content.
- Allowed exceptions: public dependency repository URLs in `Chart.yaml`, public upstream links in `README.md`/`Chart.yaml` metadata (`home`, `sources`, `icon`), public container image registries in `values.yaml`, and the ERTIS container registry `docker.ertis.uma.es` as an image repository in `values.yaml`. If unsure whether something is acceptable, ask the user.

### 5. Never invent dependency versions
- Never guess or make up the version of an external chart dependency (or a container image tag).
- If the exact version is not already known from the repository or provided by the user, **stop and ask the user**, who will verify it manually on [Artifact Hub](https://artifacthub.io/). State the dependency name and repository so it can be checked.

### 6. Every value must be documented
- Every key in `values.yaml` must have a comment directly above it explaining:
  - what it is for,
  - what filling in, enabling or changing it implies (side effects, required companion values, resources created),
  - the accepted values and the meaning of each when it is an enum-like setting (e.g. `ClusterIP` / `NodePort` / `LoadBalancer`).
- Use the [helm-docs](https://github.com/norwoodj/helm-docs) comment style (`# -- Description`) so documentation can be generated.
- Example:
  ```yaml
  service:
    # -- Kubernetes Service type used to expose the API.
    # `ClusterIP` exposes it only inside the cluster, `NodePort` also exposes it on every node
    # using `service.nodePort`, and `LoadBalancer` requests an external load balancer from the cloud provider.
    type: ClusterIP
    # -- Node port used when `service.type` is `NodePort`. Leave empty to let Kubernetes assign one.
    nodePort: ""
  ```

### 7. Professional English everywhere
- All comments, value keys, template names, helper names, variables, labels, NOTES.txt, READMEs, scripts and commit messages must be written in professional English.
- Follow standard conventions: camelCase for values keys, `<chart>.<helper>` naming for named templates in `_helpers.tpl`, Kubernetes recommended labels (`app.kubernetes.io/*`), 2-space YAML indentation.

### 8. Every chart has a README
Each chart must have a `README.md` in professional English including at least:
- The tool it deploys, with a link to its GitHub repository.
- What the tool is and what it is used for.
- Prerequisites, installation and uninstallation commands (using the `ertis` repository alias: `helm repo add ertis https://ertis-research.github.io/helm-charts/`).
- A values table (key, type, default, description) consistent with the documented `values.yaml`.

### 9. Keep the root README chart list up to date
- [README.md](README.md) contains the list of charts with their chart version and application version.
- Whenever a chart is added, removed, or its `version`/`appVersion` changes, update this list in the same change.

## Chart development conventions

- New charts use `apiVersion: v2`, declare dependencies in `Chart.yaml`, and commit the resulting `Chart.lock`.
- Any change to a chart's functional files (`Chart.yaml`, `values.yaml`, templates, scripts, dependencies) requires bumping `version` in its `Chart.yaml` following SemVer. The release workflow runs chart-releaser with `skip_existing: true`, so a changed chart whose version already exists is silently skipped and the change is never published. Changes that only touch a chart's `README.md` do not require a version bump. Bump `appVersion` only when the deployed application version changes.
- Optional components must be guarded by an `<component>.enabled` value (and `condition:` for dependencies).
- Do not hardcode namespaces; use `{{ .Release.Namespace }}`.
- Include resource requests/limits, probes and `securityContext` as configurable values where applicable.

## Useful commands

```bash
# Download/update dependencies (refreshes Chart.lock and charts/*.tgz)
helm dependency update <chart-dir>

# Lint a chart
helm lint <chart-dir>

# Render templates locally without installing
helm template test <chart-dir> -f <values-file>

# Example manual test with the repository test values
helm install test ./OpenTwins -f ./tests/opentwins-values.yaml
```

Always run `helm lint` and `helm template` on any chart you create or modify before reporting the work as done, and report the output faithfully.

## Subagents

Two project subagents are defined in [.claude/agents/](.claude/agents/):

- **`chart-explorer`** (Haiku): read-only search of files, templates and values across the repository. Use it for locating code and gathering context.
- **`chart-writer`** (Sonnet): writes and edits chart code (templates, values, Chart.yaml, READMEs) following the rules above.

Workflow: the main session plans the work and delegates to these agents when useful, then **reviews every result against the hard rules above** (lowercase names, no IPs/URLs/secrets, documented values, professional English, no invented versions, README present, root README list updated, no commits) before reporting to the user. Fix or re-delegate anything that does not comply.
