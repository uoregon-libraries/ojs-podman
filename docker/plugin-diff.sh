#!/usr/bin/env bash
#
# Compares the plugins (as "category/name") in plugin sources. Each source is
# either a plugins directory (e.g., a podman volume's _data dir) or
# "image:<ref>" to use the pristine plugins baked into an OJS image.
#
# With one or two sources, lists the plugins that only one of them has.
# Comparing a volume against the image it runs on shows exactly what came from
# the gallery or a manual upload. Use an image with the *same* OJS version as
# the volume, or core plugins added/dropped between versions show up too.
#
# With --upgrade, prints just the plugins to put back after rebuilding the
# plugins volume from a new image, one per line: those in the volume that
# neither the old image nor the new one has. Notes about plugins the upgrade
# adds to or drops from core go to stderr, so the list can be redirected to a
# file. See "Upgrading a site" in README.md.
#
# Rootless podman volumes are owned by subuids, so run this inside `podman
# unshare` when reading them directly.
set -euo pipefail

default_b=image:localhost/journals_web

usage() {
  echo "Usage: $0 <plugins dir | image:ref> [plugins dir | image:ref]"
  echo "       $0 --upgrade <volume dir> <old image:ref> <new image:ref>"
  echo
  echo "The second source defaults to $default_b"
  echo
  echo "Examples:"
  echo "  $0 vols/plugins"
  echo "  $0 vols/plugins vols/other-plugins"
  echo "  $0 --upgrade vols/plugins image:localhost/journals_web:pre-upgrade image:localhost/journals_web > restore.txt"
  exit 1
}

list_plugins() {
  local src=$1
  if [[ $src == image:* ]]; then
    podman run --rm --entrypoint find "${src#image:}" \
      /var/www/html/plugins -mindepth 2 -maxdepth 2 -type d -printf '%P\n'
  elif [[ -d $src ]]; then
    find "$src" -mindepth 2 -maxdepth 2 -type d -printf '%P\n'
  else
    echo "Not a directory or image:ref: $src" >&2
    return 1
  fi
}

# Prints a sorted list for comm, one plugin per line. An empty list prints
# nothing: echo would print a blank line, which comm treats as a plugin.
lines() {
  [[ -z $1 ]] || printf '%s\n' "$1"
}

# Plugins in list $1 that list $2 doesn't have
only_in() {
  comm -23 <(lines "$1") <(lines "$2")
}

# Plugins in both lists
in_both() {
  comm -12 <(lines "$1") <(lines "$2")
}

image_id() {
  podman image inspect --format '{{.Id}}' "${1#image:}"
}

upgrade() {
  local vol_src=$1 old_src=$2 new_src=$3

  # Building the new image moves the tag off the old one, so it's easy to end
  # up passing the new image twice, which hides every core change
  if [[ $old_src == image:* && $new_src == image:* ]] &&
    [[ $(image_id "$old_src") == $(image_id "$new_src") ]]; then
    echo "$old_src and $new_src are the same image. Tag the old image before" >&2
    echo "building the new one, and pass that tag as the old image." >&2
    exit 1
  fi

  # Plain assignments (not process substitution) so set -e catches failures,
  # e.g., permission errors from forgetting `podman unshare`
  local vol old new
  vol=$(list_plugins "$vol_src" | sort)
  old=$(list_plugins "$old_src" | sort)
  new=$(list_plugins "$new_src" | sort)

  local noncore became_core dropped
  noncore=$(only_in "$vol" "$old")
  became_core=$(in_both "$noncore" "$new")
  dropped=$(only_in "$(in_both "$vol" "$old")" "$new")

  if [[ -n $became_core ]]; then
    echo "Not listed: these are core plugins in $new_src, so its copies replace yours:" >&2
    lines "$became_core" | sed 's/^/  /' >&2
    echo >&2
  fi
  if [[ -n $dropped ]]; then
    echo "Dropped from core: these won't exist after the upgrade. If any are in use," >&2
    echo "find a replacement (e.g., in the plugin gallery) before upgrading:" >&2
    lines "$dropped" | sed 's/^/  /' >&2
    echo >&2
  fi

  only_in "$noncore" "$new"
}

if [[ ${1:-} == --upgrade ]]; then
  if [[ $# -ne 4 ]]; then
    usage
  fi
  upgrade "$2" "$3" "$4"
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
fi

src_a=$1
src_b=${2:-$default_b}

a=$(list_plugins "$src_a" | sort)
b=$(list_plugins "$src_b" | sort)

echo "Only in $src_a:"
only_in "$a" "$b" | sed 's/^/  /'
echo
echo "Only in $src_b:"
only_in "$b" "$a" | sed 's/^/  /'
