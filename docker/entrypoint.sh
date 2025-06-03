#!/bin/bash

init() {
  if [ ! -e /var/local/config/config.inc.php ]; then
    /replace-vars.sh /config-template.ini /var/local/config/config.inc.php
    chown www-data /var/local/config/config.inc.php
  fi

  su -s /bin/bash -c "ln -sf /var/local/config/config.inc.php /var/www/html/config.inc.php" - www-data
  chmod -w /var/local/config/config.inc.php
}

# When user requests bash or sh, don't run the init function
case "$@" in
  bash | sh )
  ;;

  *)
  init
esac

exec "$@"
