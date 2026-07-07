#!/usr/bin/env bash
# firewall.sh — lock the container's network down to the Anthropic API only.
#
# Default policy is DROP. Only DNS, loopback, established return traffic, and
# api.anthropic.com (plus anything in $KLAUS_HOSTS) are permitted.
# Runs as root at container start, before we drop to the `klaus` user.

set -euo pipefail

# Hosts allowed, in three layers:
#   1. api.anthropic.com                     — always (Claude needs it)
#   2. /etc/klaus/allow-hosts                — baked in by the selected modules
#                                              at setup (e.g. Gradle hosts for kmp)
#   3. $KLAUS_HOSTS                     — ad-hoc, per run:
#        KLAUS_HOSTS="pypi.org files.pythonhosted.org" klaus
module_hosts=""
[ -f /etc/klaus/allow-hosts ] && module_hosts="$(tr '\n' ' ' < /etc/klaus/allow-hosts)"
allowed="api.anthropic.com $module_hosts ${KLAUS_HOSTS:-}"

# Flush and set restrictive default policies for outbound traffic.
iptables -F OUTPUT
iptables -P OUTPUT DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP

# Loopback and established/related return traffic.
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# DNS, so hostnames resolve.
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow each host's resolved IPs (HTTPS only). One line per host, IPs stay quiet.
echo "allowed hosts:"
for host in $allowed; do
    for ip in $(getent ahostsv4 "$host" | awk '{print $1}' | sort -u); do
        iptables -A OUTPUT -p tcp -d "$ip" --dport 443 -j ACCEPT
    done
    echo "  • $host"
done
