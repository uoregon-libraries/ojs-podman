#!/bin/bash

conffile=/var/local/config/config.inc.php
init() {
  wait_for_database

  # If config.inc.php isn't present in our volume, we need to create it and get
  # it set up for the OJS web installer
  if [ ! -e $conffile ]; then
    cp /var/www/html/config.TEMPLATE.inc.php $conffile
    chown www-data $conffile
    chmod 600 $conffile
    su -s /bin/bash -c "ln -sf $conffile /var/www/html/config.inc.php" - www-data
  fi
}

# When user requests bash or sh, don't run the init function
case "$@" in
  bash | sh )
  ;;

  *)
  init
esac

exec "$@"
