#!/bin/sh
# Runs the plugin's helper against real processes under nixpkgs' names
# (.Hyprland-wrapp, .gliff-wrapped), with stubs only for gliff, gliff-server
# and ssh. Usage: behaviour.sh <plugin dir>
# shellcheck disable=SC2016 # jq filters
set -eu

plugin=$1
tmp=$(mktemp -d)
HOME=$tmp/home XDG_CONFIG_HOME=$tmp/home/.config XDG_CACHE_HOME=$tmp/home/.cache
export HOME XDG_CONFIG_HOME XDG_CACHE_HOME
mkdir -p "$HOME" "$tmp/bin" "$tmp/tab"
pids=
# shellcheck disable=SC2329 # runs from the trap
cleanup() { # children first: a killed parent leaves its sleeps behind
  set +e
  for p in $pids; do
    for c in $(pgrep -P "$p" 2>/dev/null); do pkill -P "$c" 2>/dev/null; kill "$c" 2>/dev/null; done
    kill "$p" 2>/dev/null
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

printf '%s\n' '#!/bin/sh' 'echo "gliff 0.3.1"' >"$tmp/bin/gliff"
printf '%s\n' '#!/bin/sh' 'echo "gliff-server 0.3.1"' >"$tmp/bin/gliff-server"
# ssh [-o X] [-t] [--] TARGET CMD...: run CMD here, stdin passed through.
cat >"$tmp/bin/ssh" <<'STUB'
#!/bin/sh
while [ $# -gt 0 ]; do
  case $1 in -o) shift 2 ;; -t) shift ;; --) shift; break ;; *) break ;; esac
done
shift
exec "$@"
STUB
chmod +x "$tmp/bin/"*
PATH=$tmp/bin:$PATH

# Copies of bash, so the kernel's comm is the name we need. `; :` keeps bash
# forking its child instead of exec-ing it, which would rename the process.
bash=$(command -v bash)
cp "$bash" "$tmp/.Hyprland-wrapp"
cp "$bash" "$tmp/.gliff-wrapped"
cp "$bash" "$tmp/tab/ssh"
"$tmp/.Hyprland-wrapp" -c 'sleep 600; :' &
pids="$pids $!"
# gliff's tab: an ssh child of the gliff process. Its argv is `ssh -c SCRIPT me@box`,
# so the helper sees host me@box.
"$tmp/.gliff-wrapped" -c "$tmp/tab/ssh -c 'sleep 600; :' me@box; :" --headless me@box &
pids="$pids $!"

i=0
while [ $i -lt 50 ]; do
  pgrep -x '\.Hyprland-wrapp' >/dev/null && pgrep -x '\.gliff-wrapped' >/dev/null &&
    pgrep -P "$(pgrep -x '\.gliff-wrapped')" -x ssh >/dev/null && break
  i=$((i + 1)); sleep 0.1
done

fail=0
check() { # <name> <jq-filter> <json> [jq args...]
  name=$1 filter=$2 json=$3; shift 3
  if printf '%s' "$json" | jq -e "$@" "$filter" >/dev/null; then
    echo "ok: $name"
  else
    echo "FAIL: $name"; printf '%s\n' "$json"; fail=1
  fi
}

check status '.local.installed and .local.version == "0.3.1"' \
  "$(sh "$plugin/gliff-manager.sh" status fast)"
check probe '.gliff == "0.3.1" and .hyprOwner == $u' \
  "$(sh "$plugin/gliff-manager.sh" probe me@box)" --arg u "$(id -un)"
check live '. == [{pid: .[0].pid, target: "me@box", mode: "headless"}]' \
  "$(sh "$plugin/gliff-manager.sh" live)"
exit $fail
