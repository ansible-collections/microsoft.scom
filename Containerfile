ARG EE_BASE_IMAGE="registry.redhat.io/ansible-automation-platform-25/de-minimal-rhel9:latest"

# Base build stage
FROM $EE_BASE_IMAGE as base
USER root

COPY meta/requirements.yml requirements.yml

RUN pip3 install httpx httpx_ntlm
RUN ansible-galaxy collection install -r requirements.yml --collections-path /usr/share/ansible/collections && rm -f requirements.yml
