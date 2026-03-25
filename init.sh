#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Air-Gap Infrastructure — Container Entrypoint
# ============================================================
# Validates environment, then runs the requested playbook.
#
# Build:
#   docker build -t air-gap .
#
# Run (full deployment):
#   docker run --rm \
#     -v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro \
#     -v $(pwd)/group_vars/all.yml:/air/group_vars/all.yml \
#     -e HARBOR_ADMIN_PASSWORD=secret \
#     air-gap
#
# Run with extra ansible-playbook flags:
#   docker run ... air-gap --skip-tags k8s-cluster
#   docker run ... air-gap --tags harbor,nexus
#   docker run ... air-gap --check
#
# Switch playbook (e.g. seed.yml):
#   docker run ... air-gap --playbook seed.yml -e "harbor_host=harbor.internal.local"
# ============================================================

WORKDIR=/airgapped

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[init]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
error() { echo -e "${RED}[error]${NC} $*" >&2; }

cd "$WORKDIR"

# ---- 1. SSH key --------------------------------------------
SSH_KEY_PATH="${SSH_PRIVATE_KEY_PATH:-/root/.ssh/id_rsa}"
if [[ ! -f "$SSH_KEY_PATH" ]]; then
  warn "SSH key not found at $SSH_KEY_PATH"
  warn "Mount it with: -v ~/.ssh/id_rsa:${SSH_KEY_PATH}:ro"
else
  chmod 600 "$SSH_KEY_PATH"
  info "SSH key: $SSH_KEY_PATH"
fi

# ---- 2. Warn if group_vars still has defaults --------------
if grep -q "^domain_suffix: \"internal.local\"" group_vars/all.yml 2>/dev/null; then
  warn "group_vars/all.yml uses default domain — mount your own config:"
  warn "  -v /path/to/all.yml:/air/group_vars/all.yml"
fi

# ---- 3. Validate playbooks exist ---------------------------
MISSING=()
for pb in playbooks/site.yml playbooks/seed.yml; do
  [[ ! -f "$pb" ]] && MISSING+=("$pb")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  error "Missing playbooks: ${MISSING[*]}"
  exit 1
fi
info "Playbooks OK. Run playbooks from /air, e.g.:"
info "  ansible-playbook -i inventory/hosts.yml playbooks/site.yml"

# ---- Drop into shell ---------------------------------------
exec bash
