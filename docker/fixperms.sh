#!/usr/bin/env bash

# The various dirs that OJS needs to read *and* write need to be set up so that
# others can't read or write to them. (OJS's config gets its permissions when
# the entrypoint renders it.)
for dir in /var/local/ojs-files /var/www/html/cache /var/www/html/public /var/www/html/plugins; do
  chown -R www-data:root $dir
  chmod 770 $dir
  find "$dir" \( -type f ! -perm 0660 -exec chmod 660 {} + \) -o \( -type d ! -perm 0770 -exec chmod 770 {} + \)
done
