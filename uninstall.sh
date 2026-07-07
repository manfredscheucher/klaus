#!/usr/bin/env bash
# klaus — uninstall. Removes everything setup.sh created:
#   - the shell-rc block that sources klaus.sh
#   - the Docker image
#   - the klaus-data volume (session history)
#   - the base dir (~/.klaus — login, modules, apt-packages)
#   - the dependency-cache volumes (klaus-cache / klaus-gradle / klaus-m2)
# Asks before removing the data (history + login), since that's irreversible.

set -euo pipefail

IMAGE_NAME="klaus"
# The base dir holds modules, apt-packages AND claude's config — remove it all.
CONFIG_DIR="${KLAUS_DIR:-$HOME/.klaus}"

# 1. remove the rc block (between the klaus markers).
for RC_FILE in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC_FILE" ] && grep -qF "# >>> klaus >>>" "$RC_FILE"; then
        echo "==> removing klaus block from $RC_FILE"
        sed -i.klaus-bak '/# >>> klaus >>>/,/# <<< klaus <<</d' "$RC_FILE"
    fi
done

# 2. remove the image.
if command -v docker >/dev/null 2>&1 && docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "==> removing image '$IMAGE_NAME'"
    docker rmi "$IMAGE_NAME" >/dev/null
fi

# 3. data + credentials — ask explicitly, no default (this is irreversible).
echo ""
echo "Your login, session history and image config live in $CONFIG_DIR and the"
echo "klaus-data volume. Removing them is irreversible."
ans=""
while [ "$ans" != "keep" ] && [ "$ans" != "delete" ]; do
    printf "Type 'keep' or 'delete': "
    read -r ans
done
if [ "$ans" = "delete" ]; then
    command -v docker >/dev/null 2>&1 && docker volume rm klaus-data >/dev/null 2>&1 || true
    rm -rf "$CONFIG_DIR"
    echo "==> removed data + login."
else
    echo "==> kept data + login ($CONFIG_DIR, klaus-data volume)."
fi

# Dependency caches are always safe to drop (they just re-download).
if command -v docker >/dev/null 2>&1; then
    docker volume rm klaus-cache klaus-gradle klaus-m2 >/dev/null 2>&1 || true
fi

echo "==> done. Open a new shell to drop the klaus function."
