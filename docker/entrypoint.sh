#!/bin/bash

conffile=/var/local/config/config.inc.php
init() {
  # This adds a lot of overhead to container startup, and is usually
  # unnecessary, but ensuring this happens seems like a good idea all the same.
  # At least for now.
  echo "Ensuring proper file/dir permissions..."
  fixperms.sh
  echo "Permissions set"

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
  chmod +w /var/www/html
  su -s /bin/bash -c "ln -s $conffile /var/www/html/config.inc.php" - www-data
  chmod -w /var/www/html

  # Wait for the database last: the db container is starting up in parallel, so
  # there's no point making the above operations wait on this
  echo "Waiting for database to start..."
  wait_for_database
  echo "Database ready"
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
