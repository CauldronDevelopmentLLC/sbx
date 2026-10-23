# Sourced by templates' install scripts, which run on the host.  Downloads are
# verified before they are unpacked and nothing downloaded is run.  Versions
# are installed side by side in $SBX_APPS/$app, "current" points to the newest
# and the previous one is kept for sandboxes still running it.
set -euo pipefail

dir=$SBX_APPS/$app
mkdir -p "$dir"
exec 9> "$dir/.lock"
flock 9
tmp=$(mktemp -d "$dir/.new.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
progress=--silent
[ -t 2 ] && progress=--progress-bar


log() { echo "$app: $*" >&2; }
log "Checking for the latest version"


# Usage: fetch <url> [<file>], by default into $tmp
fetch() {
  curl -fSL $progress --proto =https -o "${2:-$tmp/${1##*/}}" "$1"
}


# Usage: arch <x86_64 name> <aarch64 name>
arch() {
  case $(uname -m) in
    x86_64)  echo "$1" ;;
    aarch64) echo "$2" ;;
    *) echo "Unsupported architecture $(uname -m)" >&2; exit 1 ;;
  esac
}


# Usage: check <version>, exits if it is already current
check() {
  [ -n "$1" ] || { log "No version found"; exit 1; }
  [ "$(readlink "$dir/current" 2>/dev/null)" = "$1" ] || {
    log "Downloading $1"
    return
  }
  log "$1 is up to date"
  exit 0
}


# Usage: root <dir>, the archive's top directory if it has only one
root() {
  local entries=("$1"/*)
  if [ ${#entries[@]} = 1 ] && [ -d "${entries[0]}" ]; then
    echo "${entries[0]}"
  else echo "$1"; fi
}


# Usage: activate <version> <dir>, makes it current, removes older versions
activate() {
  local prev old
  prev=$(readlink "$dir/current" 2>/dev/null || true)
  mv "$2" "$dir/$1"
  ln -sfn "$1" "$dir/.current"
  mv -T "$dir/.current" "$dir/current"

  for old in "$dir"/*; do
    case ${old##*/} in
      current|"$1"|"$prev") ;;
      *) rm -rf "$old" ;;
    esac
  done

  log "Installed $1"
}
