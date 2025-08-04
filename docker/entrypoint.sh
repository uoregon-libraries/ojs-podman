#!/bin/bash

conffile=/var/local/config/config.inc.php
init() {
  wait_for_database

  if [ ! -e $conffile ]; then
    /replace-vars.sh /config-template.ini $conffile
    chown root:www-data $conffile
  fi

  su -s /bin/bash -c "ln -sf $conffile /var/www/html/config.inc.php" - www-data

  # Set up the app key: the OJS tool won't replace it if it's already been set
  chmod 660 $conffile
  su -s /bin/bash -c "cd /var/www/html && php ./lib/pkp/tools/appKey.php generate" - www-data
  chmod 440 $conffile
}

# When user requests bash or sh, don't run the init function
case "$@" in
  bash | sh )
  ;;

  *)
  init
esac

exec "$@"
