#!/bin/bash

conffile=/var/local/config/config.inc.php
init() {
  echo "Waiting for database to start..."
  wait_for_database
  echo "Database ready"

  # If config.inc.php isn't present in our volume, we need to create it and get
  # it set up for the OJS web installer
  if [ ! -e $conffile ]; then
    cp /var/www/html/config.TEMPLATE.inc.php $conffile
    chown www-data $conffile
    chmod 600 $conffile
  fi

  # OJS sometimes blows away our symlink after we've created it, so we just have
  # to keep forcibly creating it
  echo "Force-linking $conffile to local config"
  rm -f /var/www/html/config.inc.php
  su -s /bin/bash -c "ln -s $conffile /var/www/html/config.inc.php" - www-data
}

# When user requests bash or sh, don't run the init function
case "$@" in
  bash | sh )
  ;;

  *)
  init
esac

echo "Running $@..."
exec "$@"
