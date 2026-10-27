#!/bin/bash

conffile=/var/local/config/config.inc.php
ojsconf=/var/www/html/config.inc.php

# Mirrors how OJS reads the setting: an unquoted Off, False, 0, or blank value
# (or no setting at all) means it's not installed
is_installed() {
  grep -qiE '^\s*installed\s*=' $conffile &&
    ! grep -qiE '^\s*installed\s*=\s*(off|false|0)?\s*$' $conffile
}

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

    # The web installer runs a scheduled task that logs to files_dir *before*
    # it saves the form's "directory for uploads", and the template's "files"
    # isn't writable, so the install crashes unless this is right from the
    # start
    sed -i 's|^files_dir = files$|files_dir = /var/local/ojs-files|' $conffile
    if ! grep -q '^files_dir = /var/local/ojs-files$' $conffile; then
      echo "WARNING: couldn't set files_dir in $conffile. Set it to /var/local/ojs-files before running the web installer."
    fi

    chown www-data $conffile
    chmod 600 $conffile
  fi

  # OJS reads a copy of our config with the "${VAR}" placeholders filled in
  # from the environment. The copy is read-only to OJS, and only made here, so
  # config changes need a container restart (and .env changes need `up -d`).
  #
  # Before OJS is installed, though, the web installer has to write the real
  # file, so OJS gets a link to it instead.
  rm -f $ojsconf
  chmod +w /var/www/html
  if is_installed; then
    echo "Rendering $conffile to $ojsconf"
    if ! (umask 077 && render-config $conffile > $ojsconf); then
      rm -f $ojsconf
      exit 1
    fi
    chown root:www-data $ojsconf
    chmod 440 $ojsconf
  else
    echo "OJS isn't installed: linking $conffile for the web installer"
    su -s /bin/bash -c "ln -s $conffile $ojsconf" - www-data
  fi
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
