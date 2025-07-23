#!/bin/bash

init() {
  wait_for_database

  if [ ! -e /var/local/config/config.inc.php ]; then
    /replace-vars.sh /config-template.ini /var/local/config/config.inc.php
    chown root:www-data /var/local/config/config.inc.php
    chmod 640 /var/local/config/config.inc.php
  fi

  su -s /bin/bash -c "ln -sf /var/local/config/config.inc.php /var/www/html/config.inc.php" - www-data

  # Set up the app key: the OJS tool won't replace it if it's already been set
  php ./lib/pkp/tools/appKey.php generate
}

# When user requests bash or sh, don't run the init function
case "$@" in
  bash | sh )
  ;;

  *)
  init
esac

exec "$@"
