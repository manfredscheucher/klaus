#!/usr/bin/env bash
# build-install-modules.sh — runs during the image build (as root); not a
# command you run yourself.
# For each selected module: source it, run install_module(), and collect its
# firewall HOSTS into /etc/klaus/allow-hosts for the runtime firewall to read.

set -euo pipefail

MOD_DIR="/opt/klaus-modules"
mkdir -p /etc/klaus
: > /etc/klaus/allow-hosts

apt-get update

for mod in ${KLAUS_MODULES:-}; do
    file="$MOD_DIR/$mod.module"
    if [ ! -f "$file" ]; then
        echo "install-modules: unknown module '$mod' (no $file)" >&2
        exit 1
    fi
    echo "==> installing module: $mod"

    # Record this module's firewall hosts (from the '# HOSTS:' header line).
    hosts="$(grep -m1 '^# HOSTS:' "$file" | sed 's/^# HOSTS:[[:space:]]*//')"
    [ -n "$hosts" ] && echo "$hosts" >> /etc/klaus/allow-hosts

    # Run the module's installer.
    unset -f install_module 2>/dev/null || true
    # shellcheck disable=SC1090
    . "$file"
    install_module
done

# Generic extra apt packages (things that need no dedicated module).
if [ -n "${KLAUS_APT:-}" ]; then
    echo "==> installing extra apt packages: $KLAUS_APT"
    apt-get install -y --no-install-recommends $KLAUS_APT
fi

echo "==> module install complete"
echo "    firewall allow-hosts:"
sed 's/^/      /' /etc/klaus/allow-hosts || true
