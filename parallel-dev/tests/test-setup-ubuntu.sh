#!/usr/bin/env bash
# test-setup-ubuntu.sh - run setup.md's "Ubuntu, Debian and WSL2" steps, exactly as written, on a
# clean ubuntu:24.04 container as a normal user with sudo, then its "Check it works" steps, then a
# request to the site. The commands are read out of setup.md, so this tests the document itself.
#
# Containers have no systemd, so `systemctl reload|restart X` becomes `service X reload|restart`,
# and MariaDB and nginx are started by hand after apt installs them (on a real machine apt starts
# them). Nothing
# else in the steps is changed.
#
# The container is left behind, stopped, as `pd-setup-test` for inspection, and replaced at the
# start of the next run. Needs Docker.
set -uo pipefail

SK=$(cd "$(dirname "$0")/.." && pwd)
NAME="${PD_SETUP_CONTAINER:-pd-setup-test}"
IMAGE="${PD_SETUP_IMAGE:-ubuntu:24.04}"

# The two fenced bash blocks: the Ubuntu section's first block and "Check it works".
extract() {
    awk -v section="$1" '
        $0 ~ "^## " { insec = ($0 ~ section) }
        insec && /^```bash/ { inblk = 1; next }
        inblk && /^```/ { exit }
        inblk { print }
    ' "$SK/setup.md"
}
SETUP=$(extract "Ubuntu, Debian and WSL2")
CHECK=$(extract "Check it works")
[ -n "$SETUP" ] && [ -n "$CHECK" ] || { echo "could not read the steps out of setup.md"; exit 1; }

SETUP=$(printf '%s\n' "$SETUP" \
    | sed -E 's/sudo systemctl (reload|restart) ([^ ]+)/sudo service \2 \1/g' \
    | sed -E 's/^(curl -sSLO .*wp-cli.phar)$/sudo service mariadb start \&\& sudo service nginx start\n\1/')

docker rm -f "$NAME" >/dev/null 2>&1
docker run -d --name "$NAME" "$IMAGE" sleep infinity >/dev/null || exit 1
trap 'docker stop -t 1 "$NAME" >/dev/null 2>&1' EXIT

docker exec "$NAME" bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq sudo curl ca-certificates >/dev/null
    useradd -m -s /bin/bash dev
    echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev && chmod 0440 /etc/sudoers.d/dev
' || { echo "container preparation failed"; exit 1; }
docker cp "$SK" "$NAME:/home/dev/parallel-dev" && docker exec "$NAME" chown -R dev:dev /home/dev/parallel-dev

run_as_dev() {
    docker exec -e DEBIAN_FRONTEND=noninteractive -e USER=dev -e HOME=/home/dev -u dev -w /home/dev "$NAME" bash -c "set -e; SKILL=/home/dev/parallel-dev; $1"
}

echo "=== setup.md: Ubuntu steps"
if ! run_as_dev "$SETUP"; then echo "FAIL: setup steps"; exit 1; fi
echo "=== setup.md: chmod o+x \$HOME (the note under the steps)"
run_as_dev 'chmod o+x "$HOME"'
echo "=== setup.md: Check it works"
out=$(run_as_dev "$CHECK" 2>&1); echo "$out"
code=$(printf '%s\n' "$out" | tail -1)
if [ "$code" = 200 ]; then
    echo "PASS: http://hello-world.localhost:8081/ answered 200"
else
    echo "FAIL: expected 200, got '$code'"; exit 1
fi
echo "=== a symlinked plugin's static asset through nginx"
run_as_dev 'mkdir -p ~/dev/hello-plugin && echo "body{}" > ~/dev/hello-plugin/a.css && "$SKILL/scripts/create-site.sh" hello-plugin >/dev/null && curl -s -o /dev/null -w "%{http_code}\n" http://hello-plugin.localhost:8081/wp-content/plugins/hello-plugin/a.css' | tail -1 | grep -qx 200 \
    && echo "PASS: plugin asset 200" || { echo "FAIL: plugin asset"; exit 1; }
echo "all passed"
