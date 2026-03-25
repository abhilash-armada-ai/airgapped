# Air-Gap Infrastructure Deployment

Ansible-based toolkit for deploying a self-contained Kubernetes infrastructure in air-gapped (no internet) environments. Provisions a kubeadm cluster and deploys a full suite of internal services — container registry, artifact repo, Git server, TLS CA, and object storage.

## Services Deployed

| Service | Purpose |
|---------|---------|
| [Harbor](https://goharbor.io) | Container & Helm OCI registry with proxy caching |
| [Nexus](https://www.sonatype.com/products/nexus-repository) | APT, PyPI, and raw artifact proxy |
| [Gitea](https://gitea.com) | Internal Git server with repository mirroring |
| [step-ca](https://smallstep.com/docs/step-ca) | Private ACME CA for internal TLS certificates |
| [SeaweedFS](https://github.com/seaweedfs/seaweedfs) | S3-compatible object storage |
| nginx-ingress | Ingress controller |
| local-path-provisioner | Node-local persistent storage |

## Prerequisites

- Ansible control node (bastion) with SSH access to all cluster nodes
- `kubectl` and `helm` on the bastion (or use the Docker image — see below)
- Ansible collections: `kubernetes.core >= 6.3.0`, `community.general >= 12.4.0`

```bash
ansible-galaxy install -r requirements.yml
```

For the **seeding** playbook (run from an internet-connected machine):
- `skopeo` for mirroring container images
- `helm` for pulling/pushing charts to Harbor OCI

## Configuration

All configuration lives in `group_vars/all.yml`. At minimum set:

```yaml
domain_suffix: "your.domain"          # Base domain for all services

k8s_cluster:
  masters:
    - hostname: master-1
      ip: 192.168.1.10
  workers:
    - hostname: worker-1
      ip: 192.168.1.20
  ssh:
    user: ubuntu
    private_key_path: ~/.ssh/id_rsa
```

### Secrets (Environment Variables)

Secrets are read from environment variables with fallback defaults:

| Variable | Service | Default |
|----------|---------|---------|
| `HARBOR_ADMIN_PASSWORD` | Harbor | `Harbor12345` |
| `NEXUS_ADMIN_PASSWORD` | Nexus | `admin123` |
| `GITEA_ADMIN_PASSWORD` | Gitea | `Gitea12345` |
| `STEP_CA_PASSWORD` | step-ca | `StepCA12345` |
| `SEAWEEDFS_ACCESS_KEY` | SeaweedFS | `minioadmin` |
| `SEAWEEDFS_SECRET_KEY` | SeaweedFS | `minioadmin` |

> Change all defaults before deploying to production.

### Disabling Components

Set any of these to `false` in `group_vars/all.yml` to skip a service:

```yaml
deploy_k8s_cluster: false   # Skip K8s install (use existing cluster)
deploy_ingress: true
deploy_step_ca: true
deploy_storage: true
deploy_harbor: true
deploy_nexus: true
deploy_gitea: true
deploy_seaweedfs: true
```

### DNS / `/etc/hosts`

All services are exposed via ingress at `<service>.<domain_suffix>`. After deployment, add entries to `/etc/hosts` on each node (or configure your DNS server):

```
<ingress-ip>  harbor.internal.local
<ingress-ip>  nexus.internal.local
<ingress-ip>  gitea.internal.local
<ingress-ip>  ca.internal.local
<ingress-ip>  s3.internal.local
```

Get the ingress IP after deployment:

```bash
kubectl get svc -n ingress-nginx
```

## Deployment Workflow

### Step 1 — Configure

Edit `group_vars/all.yml` with your node IPs, domain, and credentials.

### Step 2 — (Optional) Seed registries

Run this from an **internet-connected** machine before the main deployment. It mirrors container images, Helm charts, and binary artifacts into Harbor and Nexus so cluster nodes never need internet access:

```bash
ansible-playbook playbooks/seed.yml \
  -e "harbor_host=harbor.internal.local"
```

### Step 3 — Deploy

```bash
# Full deployment (K8s cluster + all services)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Infrastructure only (use existing K8s cluster)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --skip-tags k8s-cluster

# Specific components only
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags harbor,nexus

# Dry-run (check mode)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check
```

### Step 4 — Kubeconfig on bastion

The bastion must have a valid kubeconfig before the service deployment plays run. After the K8s cluster play completes, copy it from the master:

```bash
mkdir -p ~/.kube
scp ubuntu@<master-ip>:/etc/kubernetes/admin.conf ~/.kube/config
kubectl cluster-info   # verify connectivity
```

### Service URLs (default domain)

| Service | URL | Credentials |
|---------|-----|-------------|
| Harbor | `https://harbor.internal.local` | `admin` / `$HARBOR_ADMIN_PASSWORD` |
| Nexus | `https://nexus.internal.local` | `admin` / `$NEXUS_ADMIN_PASSWORD` |
| Gitea | `https://gitea.internal.local` | `gitea_admin` / `$GITEA_ADMIN_PASSWORD` |
| step-ca | `https://ca.internal.local` | — |
| SeaweedFS S3 | `https://s3.internal.local` | `$SEAWEEDFS_ACCESS_KEY` / `$SEAWEEDFS_SECRET_KEY` |

## Docker Workflow

```bash
# Build the image
./build.sh

# Run (validates environment, drops into shell at /airgapped)
docker run -it --rm \
  -v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro \
  -v $(pwd)/group_vars/all.yml:/airgapped/group_vars/all.yml \
  -v ~/.kube/config:/root/.kube/config:ro \
  -e HARBOR_ADMIN_PASSWORD=secret \
  air-gap

# Then run playbooks from inside the container
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --skip-tags k8s-cluster
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags harbor,nexus
```

Custom image name or tag:

```bash
IMAGE_NAME=air-gap IMAGE_TAG=v1.0 ./build.sh
PLATFORM=linux/arm64 ./build.sh
```

## Available Tags

| Tag | Component |
|-----|-----------|
| `k8s-cluster` | Kubernetes cluster (kubeadm) |
| `prerequisites` | Pre-flight checks |
| `ingress` | nginx-ingress controller |
| `step-ca` | Private CA |
| `storage` | local-path-provisioner |
| `harbor` | Container registry |
| `nexus` | Artifact repository |
| `gitea` | Git server |
| `seaweedfs` | Object storage |

## Repository Structure

```
.
├── playbooks/
│   ├── site.yml              # Main deployment playbook
│   ├── seed.yml              # Registry seeding (internet-connected machine)
│   └── roles/                # Per-service Ansible roles
├── group_vars/
│   └── all.yml               # All configuration variables
├── inventory/
│   └── hosts.yml             # Inventory (masters/workers added dynamically)
├── requirements.yml          # Ansible Galaxy collections
├── ansible.cfg               # Ansible configuration
├── Dockerfile                # Container image for running deployments
├── init.sh                   # Container entrypoint (validates env, opens shell)
└── build.sh                  # Docker build helper
```

## Deployment Order

```
K8s cluster → prerequisites → ingress → step-ca → storage
            → harbor → nexus → gitea → seaweedfs
```

> **Note:** step-ca deploys before storage because the cert-manager ClusterIssuer must exist before other services can request TLS certificates.
