FROM python:3.14-trixie

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client \
    sshpass \
    git \
    curl \
    gnupg \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install kubectl (latest stable)
RUN KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt) \
    && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
       -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Install Helm (latest stable)
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Ansible and Python dependencies
RUN pip install --no-cache-dir \
    "ansible-core==2.20.4" \
    "kubernetes==35.0.0" \
    "openshift==0.13.2" \
    pyyaml \
    jinja2 \
    requests

WORKDIR /airgapped

# Copy project files
COPY requirements.yml .
COPY ansible.cfg .
COPY inventory/ inventory/
COPY group_vars/ group_vars/
COPY playbooks/ playbooks/

# Pre-install Ansible Galaxy collections
RUN ansible-galaxy collection install -r requirements.yml --timeout 300


# Copy entrypoint
COPY init.sh /init.sh
RUN chmod +x /init.sh

# SSH key directory — mount your key at runtime:
#   -v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

ENTRYPOINT ["/init.sh"]
