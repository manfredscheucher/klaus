# klaus — containerized Claude Code (Ubuntu base, modular toolchains)
#
# Minimal by default: this image installs only the modules you select at setup
# time (see modules/ and setup.sh). Everything Claude can see is mounted in at
# runtime; on start the container firewalls its network to the Anthropic API
# (plus any hosts required by the selected modules — see firewall.sh).

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Base tools + what the firewall/entrypoint need (iptables, gosu).
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
        curl \
        less \
        ripgrep \
        iptables \
        gosu \
    && rm -rf /var/lib/apt/lists/*

# Create the unprivileged user Claude runs as (named 'klaus'). No fixed UID:
# ubuntu:24.04 already ships a user at UID 1000, so we let useradd pick a free
# one. Pre-create the cache dirs owned by klaus so the named cache volumes
# (mounted here at run time) inherit klaus ownership and stay writable.
RUN useradd -m -s /bin/bash klaus \
    && mkdir -p /home/klaus/.cache /home/klaus/.gradle /home/klaus/.m2 \
                /home/klaus/.local/share/claude /home/klaus/.claude \
    && chown -R klaus:klaus /home/klaus
ENV HOME=/home/klaus

# --- selected modules -------------------------------------------------------
# setup.sh copies the chosen module files here and passes their names + any
# extra apt packages as build args. Each module's install_module() runs as root.
ARG KLAUS_MODULES=""
ARG KLAUS_APT=""
ARG KLAUS_ANDROID=""

# Build context is the repo root (so modules/ is visible); the Dockerfile and
# the image scripts live under image/.
COPY modules/ /opt/klaus-modules/
COPY image/build-install-modules.sh /usr/local/bin/build-install-modules.sh
RUN chmod +x /usr/local/bin/build-install-modules.sh \
    && KLAUS_MODULES="$KLAUS_MODULES" KLAUS_APT="$KLAUS_APT" \
       KLAUS_ANDROID="$KLAUS_ANDROID" \
       /usr/local/bin/build-install-modules.sh \
    && rm -rf /var/lib/apt/lists/*

# --- firewall + entrypoint --------------------------------------------------
COPY image/firewall.sh image/entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/firewall.sh /usr/local/bin/entrypoint.sh

WORKDIR /workspace

# Runs as root so the firewall can set iptables rules; entrypoint.sh drops to
# the `klaus` user before launching claude.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
