#!/usr/bin/env bash

# Config file needs special treatment: it shouldn't be readable by anybody but
# www-data, and it shouldn't be writeable at all. If a user needs to write to
# it, they have to change things on their own after the container is up.
chown www-data:root /var/local/config/
chmod 770 /var/local/config
find /var/local/config -type f -exec chown www-data:root {} \;
find /var/local/config -type f -exec chmod 460 {} \;

# The various dirs that OJS needs to read *and* write still need to be set up
# so that others can't read or write to them
for dir in /var/local/ojs-files /var/www/html/cache /var/www/html/public /var/www/html/plugins; do
  chown -R www-data:root $dir
  chmod 770 $dir
  find $dir -type f -exec chmod 660 {} \;
  find $dir -type d -exec chmod 770 {} \;
done
