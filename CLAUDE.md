# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Air-gap infrastructure deployment toolkit using Ansible. Deploys a kubeadm-based Kubernetes cluster and a suite of internal services (Harbor, Nexus, Gitea, step-ca, SeaweedFS) onto it, all designed to operate without internet access. A separate seeding playbook populates the registries from an internet-connected machine.

## Commands

```bash
# Install Ansible dependencies
ansible-galaxy install -r requirements.yml

# Full deployment
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Skip K8s cluster installation (use existing cluster)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --skip-tags k8s-cluster

# Deploy specific components only
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags harbor,nexus

# Seed air-gap registries (run from internet-connected machine)
ansible-playbook playbooks/seed.yml -e "harbor_host=harbor.internal.local"
```

### Docker Workflow

```bash
# Build the image
./build.sh

# Custom name/tag
IMAGE_NAME=air-gap IMAGE_TAG=v1.0 ./build.sh

# Run container (drops into shell after validation)
docker run -it --rm \
  -v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro \
  -v $(pwd)/group_vars/all.yml:/airgapped/group_vars/all.yml \
  -e HARBOR_ADMIN_PASSWORD=secret \
  air-gap

# Then inside the container, run playbooks manually:
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --skip-tags k8s-cluster
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags harbor,nexus
```

**Docker files:**
- `Dockerfile` — image based on `python:3.13-slim`; includes kubectl, Helm, ansible-core, and pre-installed Galaxy collections.
- `init.sh` — entrypoint: validates SSH key, warns on default config, checks playbooks exist, then drops into bash.
- `build.sh` — wrapper around `docker build`; respects `IMAGE_NAME`, `IMAGE_TAG`, `PLATFORM` env vars.

No test suite or linter is configured.

## Architecture

### Playbooks

- **`playbooks/site.yml`** — Main playbook. Three plays: (1) build dynamic inventory from `group_vars/all.yml`, (2) install K8s on master/worker nodes, (3) deploy infrastructure services on bastion host.
- **`playbooks/seed.yml`** — Runs on an internet-connected machine. Uses skopeo to mirror container images to Harbor, pulls/pushes Helm charts to Harbor OCI, downloads binaries to Nexus.

### Execution Order

K8s cluster install runs first on remote nodes, then bastion-local services deploy in dependency order:
`prerequisites → ingress → step-ca → storage → harbor → nexus → gitea → seaweedfs`

step-ca deploys before storage because the ClusterIssuer must exist before other services request TLS certificates.

### Role Numbering vs. Execution Order

Role directory names (e.g., `03_storage`, `04_step-ca`) do NOT match execution order in `site.yml`. step-ca (role `04_`) runs before storage (role `03_`). Trust the order in `site.yml`, not the directory prefix.

### Inventory Model

- **Bastion host** runs as `localhost` with `ansible_connection: local` — it has kubectl access and runs all service deployments.
- **Master/worker nodes** are defined in `group_vars/all.yml` under `k8s_cluster.masters` and `k8s_cluster.workers`, then added dynamically via `add_host` in Play 0.

### Common Helm Deploy Pattern

Most roles deploy via `include_tasks: roles/common/tasks/helm-deploy.yaml` with these variables:
- `deploy_name`, `deploy_namespace`, `deploy_chart_repo`, `deploy_chart_name`, `deploy_chart_version`

Values files are resolved via: `role_path + '/templates/charts/' + deploy_chart_name + '/values.yaml.j2'`

**Exception:** Nexus uses raw Kubernetes manifests (4 templates in `templates/manifests/`) because Sonatype deprecated their Helm chart.

### Post-Deploy API Configuration

Harbor, Nexus, Gitea, and SeaweedFS all have a second task file for post-deployment configuration via their respective REST APIs (creating projects, repositories, mirrors, buckets). These use `ansible.builtin.uri` with `failed_when` handling 409 (conflict/already-exists) as success.

### TLS Chain

step-ca → cert-manager ClusterIssuer (`step-ca-issuer`) → per-service Certificate resources → TLS Secrets referenced by Ingress. All TLS-enabled services (Harbor, Nexus, Gitea, SeaweedFS) follow this pattern.

## Key Conventions

### Variable Configuration

- All configuration lives in `group_vars/all.yml`. Role `defaults/main.yml` files provide fallbacks.
- Component toggles: `deploy_harbor`, `deploy_nexus`, etc. — always check with `| default(true) | bool`.
- Secrets come from environment variables with hardcoded fallbacks: `lookup('env', 'HARBOR_ADMIN_PASSWORD') | default('Harbor12345', true)`.
- Service hostnames are constructed as `<service>.{{ domain_suffix }}` (default: `internal.local`).

### Ansible Patterns

- Use `kubernetes.core.k8s` and `kubernetes.core.k8s_info` modules, not shell/kubectl commands.
- Use `no_log: true` on any task handling credentials.
- Readiness checks use `k8s_info` with `until`/`retries`/`delay` loops on Deployment/StatefulSet conditions.
- Task-level variables use `_` prefix for namespace isolation (e.g., `_harbor_namespace`).
- Idempotency: API configuration tasks handle 409 status codes gracefully (resource already exists).

### Templates

- Helm values are Jinja2 templates (`values.yaml.j2`) under each role's `templates/charts/<chart>/`.
- Manifest templates (Nexus, storage) are under `templates/manifests/`.
- All templates reference variables from `group_vars/all.yml` and role defaults.

## Available Tags

`k8s-cluster`, `prerequisites`, `ingress`, `storage`, `step-ca`, `harbor`, `nexus`, `gitea`, `seaweedfs`
