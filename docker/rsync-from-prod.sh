#!/usr/bin/env bash
set -eu

source ./docker/mirror-vars.sh
dest="${1:-}"

if [ -z "$dest" ]; then
  echo "Usage: $0 <destination>"
  exit 1
fi

for syncdir in config public-files private-files plugins; do
  sudo rsync -avz -e ssh --delete --stats --exclude="temp/" --progress \
    --rsh="sudo -u $dev ssh $dev@$pod_host sudo -u $podman_user /usr/local/bin/podman-rsync.sh $pod_subdir" \
    ":/mnt/$syncdir/" "$dest/$syncdir/"
done

sudo chown -R $(id -u):$(id -g) "$dest"

echo
echo "Sync complete. If '$dest' is your compose mount point, execute 'fixperms.sh'"
echo "in a running web container or the app won't run correctly."
