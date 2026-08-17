#!/usr/bin/env bash
set -eu

source ./docker/mirror-vars.sh
for syncdir in public-files private-files plugins; do
  sudo rsync -avz -e ssh --delete --stats --exclude="temp/" --progress \
    --rsh="sudo -u $dev ssh $dev@$pod_host sudo -u $podman_user /usr/local/bin/podman-rsync.sh $pod_subdir" \
    ":/mnt/$syncdir/" ./vols/$syncdir/
done
