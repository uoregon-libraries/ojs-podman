#!/bin/bash

conffile=/var/local/config/config.inc.php
ojsconf=/var/www/html/config.inc.php

init() {
  # This adds a lot of overhead to container startup, and is usually
  # unnecessary, but ensuring this happens seems like a good idea all the same.
  # At least for now.
  echo "Ensuring proper file/dir permissions..."
  fixperms.sh
  echo "Permissions set"

  # If config.inc.php isn't present in our volume, start from our base config,
  # which takes its per-environment settings from .env
  if [ ! -e $conffile ]; then
    cp /usr/local/share/ojs/config.base.inc.php $conffile
    chown www-data $conffile
    chmod 600 $conffile
  fi

  # OJS can't tell the public scheme and port from behind our proxies, so
  # Apache passes these to it (see docker/config/htaccess). The config uses
  # HTTPS, too.
  case "$PUBLIC_SCHEME" in
    http) export HTTPS=off SERVER_PORT=80 ;;
    https) export HTTPS=on SERVER_PORT=443 ;;
    *)
      echo "PUBLIC_SCHEME must be http or https, not \"$PUBLIC_SCHEME\""
      exit 1
      ;;
  esac
  if [ -n "$PUBLIC_PORT_SUFFIX" ]; then
    export SERVER_PORT=${PUBLIC_PORT_SUFFIX#:}
  fi

  # OJS reads a copy of our config with the "${VAR}" placeholders filled in
  # from the environment. The copy is read-only to OJS, and only made here, so
  # config changes need a container restart (and .env changes need `up -d`).
  # Even the web installer can't write it, so it shows what it would have
  # written instead.
  echo "Rendering $conffile to $ojsconf"
  rm -f $ojsconf
  if ! (umask 077 && render-config $conffile > $ojsconf); then
    rm -f $ojsconf
    exit 1
  fi
  chown root:www-data $ojsconf
  chmod 440 $ojsconf

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
