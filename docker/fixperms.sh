#!/usr/bin/env bash

# Config file needs special treatment: it shouldn't be readable by anybody but
# www-data, and it shouldn't be writeable at all. If a user needs to write to
# it, they have to change things on their own after the container is up.
chown www-data:root /var/local/config/
chmod 700 /var/local/config
find /var/local/config -type f -exec chown www-data:root {} \;
find /var/local/config -type f -exec chmod 400 {} \;

# The various dirs that OJS needs to read *and* write still need to be set up
# so that others can't read or write to them
chown -R www-data:root /var/local/ojs-files /var/www/html/cache /var/www/html/public /var/www/html/plugins
chmod -R g-rwx /var/local/ojs-files /var/www/html/cache /var/www/html/public /var/www/html/plugins
chmod -R o-rwx /var/local/ojs-files /var/www/html/cache /var/www/html/public /var/www/html/plugins
