#!/usr/bin/env bash
#
# Connects to our podman host, using the setup we describe in the
# "podman-rsync-proxy" project, to run mysqldump commands
set -eu

mkdir -p ./exports/db
source ./docker/mirror-vars.sh

echo "Mirroring database structure..."
ssh $dev@$pod_host sudo -u $podman_user /usr/local/bin/podman-mysqldump.sh $pod_subdir $service \
    -hdb -d ojs \
    > ./exports/db/001-struct.sql
echo "Done (structure)."

# Prod's sessions are skipped, or prod's session cookies would log people in
# wherever this dump is imported. See "Sessions and cookies" in README.md.
echo "Mirroring data..."
ssh $dev@$pod_host sudo -u $podman_user /usr/local/bin/podman-mysqldump.sh $pod_subdir $service \
    -hdb -t --ignore-table=ojs.sessions ojs \
    > ./exports/db/002-data.sql
echo "Done (core)."

echo "Done."
