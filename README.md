# OJS Podman

(Technically podman or docker compose work)

This project builds a docker image for OJS, downloading a stable version of
their production-ready app, and providing configuration for running in
production or locally.

## Architecture / Overview

The docker image definition (`Dockerfile`) is set up to give us as much
consistency as possible across environments. No local code is copied into the
image other than "wrapper" stuff like Apache overrides, entrypoint script, etc.

OJS's config is built into the image too: on startup, the entrypoint renders
our base config into OJS's code directory, filling in values from the
environment (see [Config](#config)).

Requests pass through a few services before reaching OJS:

- **proxy** (Caddy) is the reverse-proxy in front of the whole stack
- **tps** ([Turnstile Proxy Server][tps]) blocks some form submissions until
  people pass a Cloudflare Turnstile challenge
- **web** is Apache + PHP running OJS
  - Never expose this directly: bots can then skip TPS entirely

[tps]: <https://github.com/uoregon-libraries/turnstile-proxy-server>

Two more services run the same image as web, for OJS's background work:

- **worker** runs queued jobs
- **scheduler** runs OJS's scheduled tasks every minute, so the host doesn't
  need a cron job for them (and shouldn't have one, or tasks run twice)

Note: rootless podman hides who connects to a published port, so Caddy trusts
every request's X-Forwarded-For header. Make sure only your front proxy can
reach that port, or clients can claim any IP address. If Caddy *can* see the
front proxy's address (e.g., under rootful podman), list it in `.env`'s
`EXTRA_TRUSTED_PROXIES`.

## Setup

### `.env`

You must have a `.env` file: copy `.env.example` and edit it. It holds the
settings that change per environment (URLs, passwords, TPS keys, etc.), which
compose fills into the compose files.

- Don't put environment vars in compose overrides. Overrides are for
  structural stuff like published ports and volumes.
- After changing `.env`, run `up -d`, not `restart`: env changes only apply
  when compose recreates a container.
- Vars exported in your shell override `.env`, so don't export any of them.

### Compose

We've set up our compose files to reflect the complexity of needing to combine
services with overrides on a per-service basis, relying heavily on the compose
spec's "include" directive. This approach makes it easier to set up systems
that rely on the same base services, but have small tweaks per environment.

**Major caveat, though**: it turns out some versions (maybe all) of
podman-compose do *not* support the "include" directive! If using podman,
you'll want to either set up the compose files manually, or use `docker compose
config --no-interpolate --no-normalize --no-path-resolution -f ...` to have a
flat compose setup generated for you.

To use compose, you must set up a compose.yml *and* any overrides you want for
a given environment. We provide a [compose.yml example][2], which is just a
very simple setup for combining the OJS, DB, and proxy service definitions.
There's also an [example compose override][3] for structural changes per
environment (ports, dependencies, volumes) if you want to have a base
`compose.yml` that defines a core setup you reuse across environments.

We strongly recommend familiarizing yourself not only with the [compose
spec][1], but also with the details of [using multiple compose files][4].
Understanding `include` and `extend`, how overrides work, what merging does,
etc. can be critical to making your project work well across environments.

[1]: <https://docs.docker.com/reference/compose-file/>
[2]: <compose-example.yml>
[3]: <compose.override-example.yml>
[4]: <https://docs.docker.com/compose/how-tos/multiple-compose-files/>

### Config

The OJS base config is modified to have fake-env-var substitution
(`docker/config/config.base.inc.php`), which is "rendered" on container startup
so that all configuration can be done in a more cloud-friendly way. Not all
settings are env vars, we're altering the file as needed. One big downside is
that upgrades require carefully reviewing the difference between configuration
files.

General overview:

- Settings that change per environment (URLs, allowed hosts, database, secrets,
  mail server, OAI repository ID, session cookie name) are filled in from
  `.env` (see [Placeholders](#placeholders)). Most of the URL-related ones are
  built from `PUBLIC_SCHEME`, `PUBLIC_HOST`, and `PUBLIC_PORT_SUFFIX`.
- Settings the stack requires are already set: `files_dir` is
  `/var/local/ojs-files`, `restful_urls` and `trust_x_forwarded_for` are On,
  mail goes out over SMTP, and `job_runner` and `task_runner` are Off, since
  the "worker" and "scheduler" services do that work
- Settings that are the same in every environment are hard-coded for UO, e.g.,
  `time_zone` and `enable_beacon`

#### Placeholders

OJS doesn't read environment variables, so the entrypoint fakes it: when the
container starts, any `${VAR}` in the config file is replaced with the value
of the `VAR` environment variable. For example, from the base config:

```ini
installed = ${OJS_INSTALLED}
base_url = "${PUBLIC_URL}"
allowed_hosts = '${OJS_ALLOWED_HOSTS}'
password = "${MYSQL_PASSWORD}"
smtp_port = ${OJS_SMTP_PORT}
```

Notes (mostly just for devs):

- The vars come from `.env`, but only the ones `ojs.compose.yml` passes to
  the container: the `MYSQL_` vars, and some `PUBLIC_` and `OJS_` ones. To add
  one, add it there, to `.env.example`, and to the base config.
- The exception is `HTTPS`, which the entrypoint sets to "on" or "off" from
  `PUBLIC_SCHEME`. It also passes that to OJS, along with the public port,
  since OJS can't tell either one from behind our proxies.
- Put text in quotes. Leave on/off settings and numbers unquoted: OJS reads a
  quoted "Off" as text, which counts as *on*.
- If the config uses a var that's blank or unset, the container won't start,
  and its log says what's missing.

OJS reads a rendered copy of the config, which is read-only and only made at
startup. So **after editing the base config, rebuild and run `up -d`**, and
after editing `.env`, run `up -d`.

#### New site

1. In `.env`, leave `OJS_INSTALLED` at "Off", and generate the secrets (see
   `.env.example`).
2. Start the stack and visit the site to get OJS's web installer.
3. Fill in the installer's form:
   - The "directory for uploads" must be `/var/local/ojs-files`
   - The database settings must match the `MYSQL_` vars in `.env`. For dev
     that's "db" for the host, and "ojs" for the username, password, and
     database name.
4. When the install is done, OJS says it couldn't write the config, and shows
   what it would have written. That's expected: OJS's copy of the config is
   read-only, and the base config already gets those settings from `.env`.
   (Ignore the app key it shows, too: OJS uses `OJS_APP_KEY`.)
5. Set `OJS_INSTALLED=On` in `.env`, and run `up -d`.

Since the installer can't write the config, its time zone and OAI repository
ID fields don't do anything: OJS uses the base config's time zone and
`OJS_OAI_REPOSITORY_ID`.

#### Existing site

For a site whose database is already set up (e.g., a migration from another
server):

- Set `OJS_INSTALLED=On`
- Copy the old config's `app_key`, `salt`, and `api_key_secret` into `.env`. If
  it doesn't have an app key (older OJS versions don't), generate one (see
  `.env.example`).
- Set `OJS_OAI_REPOSITORY_ID` to the old config's `repository_id`, which must
  never change on a live site
- Convert anything else the old site customized into `.env` variables if it
  differs between sites. Diff the old config against the base config to find
  those settings. If there are settings that aren't being rendered in our base
  configuration, you will need to make a code change.

### Container logs

Each service writes its stdout/stderr to its own file in `CONTAINER_LOG_DIR`
(`web.log`, `proxy.log`, etc.), so logs survive restarts and `down`.
Production needs logrotate set up to avoid filling the disk. See
[docs/container-logs.md](docs/container-logs.md).

### TPS

POSTs to OJS's "user" and "login" pages (registration, login, password resets,
and subscription purchases) have to get past a Cloudflare Turnstile challenge
(via [TPS][tps]). Nothing else is challenged for now: OJS has a lot of AJAX
requests, which would silently fail, which can sometimes cause hard-to-debug
problems. See `docker/config/Caddyfile` for details.

TPS requires some `.env` vars to run:

- `TURNSTILE_SITE_KEY` and `TURNSTILE_SECRET_KEY`: these come from a Turnstile
  widget in Cloudflare's dashboard. For dev, Cloudflare's test keys work fine.
- `JWT_SIGNING_KEY`: signs the TPS cookie, must be long and random in
  production. A bot that figures it out can skip TPS.

### Running under systemd

On servers, the stack runs as a rootless podman *user* unit belonging to the
podman user. That user needs lingering (`sudo loginctl enable-linger <user>`)
so the unit starts at boot without anybody logging in.

`systemd/ojs@.service` is a template unit, which keeps host paths out of the
repo: the instance name is the checkout's path, escaped, and the unit uses that
as its working directory. `/path/to/ojs/prod` becomes
`ojs@path-to-ojs-prod.service`, so prod and dev can run side by side from one
unit file.

Install it as the podman user, from the checkout:

```bash
mkdir -p ~/.config/systemd/user
cp systemd/ojs@.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now "ojs@$(systemd-escape --path "$PWD").service"

# Day to day (tab completion fills in the instance name)
systemctl --user status ojs@path-to-ojs-prod
journalctl --user -u ojs@path-to-ojs-prod
```

Notes:

- Copy the unit; don't `systemctl link` it. Linked units outside systemd's own
  directories can run afoul of SELinux, and `disable` deletes the link. After
  changing the unit in the repo, copy it again and `daemon-reload`.
- `systemctl --user` needs the user's session bus. `ssh` in as the user, don't
  `sudo` to switch users. It gets messy.
- The unit runs `podman compose up` with no service names, so it starts
  everything `compose.yml` includes. Choose services there, not in the unit.
- Stopping the unit runs `podman compose down`, which removes the containers
  (not volumes). Container logs survive since they're in `CONTAINER_LOG_DIR`.

### Volume files

Don't count on a volume's files being in podman's volume directory
(`~/.local/share/containers/storage/volumes`), or wherever `podman volume
inspect` says its `Mountpoint` is. A volume with `driver_opts` (a bind to a
`device` directory, as in `compose.override-example.yml`) keeps its files in
the device directory. Its mountpoint only shows them inside `podman unshare`,
and only while a container is using the volume. Anywhere else it's an empty
directory: reading it finds nothing, and files written there never reach a
container.

So when a task needs a volume's files:

- Copy them with `docker/volsync.sh`, which runs rsync (inside `podman
  unshare`) on the directory that really holds a volume's files. Name a volume
  as `vol:<name>`:
  ```bash
  ./docker/volsync.sh vol:ojs-prod_plugins /path/to/backup/plugins
  ```
- To start a volume over, empty it from a container that mounts it (e.g., the
  dev db volume in [Mirror prod to staging](#mirror-prod-to-staging-dev)).
  Don't remove and recreate it: `podman volume rm` doesn't delete a device
  directory's files, so the "new" volume still has them, and podman won't copy
  an image's files into a volume that isn't empty.

## Mirror prod to staging ("dev")

*Our "dev" site isn't really dev, but we named it that, so we're stuck with it.*

Mirroring data from production to dev is easiest done on the container host via
rsync and SQL exports.

```bash
# (ssh into the server as the podman user, and cd to the dev checkout)

# Mirror raw files (see "Volume files" above for why this uses volsync.sh)
./docker/volsync.sh -vP --delete --exclude=usageStats/archive/ --exclude=temp/ vol:ojs-prod_private-files vol:ojs-dev_private-files
./docker/volsync.sh -vP --delete vol:ojs-prod_public-files vol:ojs-dev_public-files

# Read "Mirroring plugins" below before using this to test an upgrade
./docker/volsync.sh -vP --delete vol:ojs-prod_plugins vol:ojs-dev_plugins
```

The SQL dump is slightly more annoying; you *could* rsync, but that's not
recommended: you have to shut down prod to avoid copying files that are in use,
and if there's any version difference in prod's MariaDB and dev's, you'll run
into problems and have to do a DB dump anyway.

*(This can also be a risk with the rsync commands above, but a half-written PDF
only messes up displaying, while a half-written MariaDB table means the
database won't start up.)*

```bash
# (as the podman user, *not* inside the rootless namespace)

# We export the structure separately from the data. I don't remember why, but
# it was important!
#
# The data skips the sessions table (see below)
export devpath=/path/to/ojs/dev
/usr/local/bin/podman-mysqldump.sh ojs-prod web -hdb -d ojs > $devpath/exports/db/001-struct.sql
/usr/local/bin/podman-mysqldump.sh ojs-prod web -hdb -t --ignore-table=ojs.sessions ojs > $devpath/exports/db/002-data.sql
```

Then:

- Stop dev and empty its db volume, since MariaDB only imports into an empty
  database. Don't `podman volume rm` it (see [Volume files](#volume-files)).
  ```bash
  podman run --rm --entrypoint find -v ojs-dev_db:/vol localhost/ojs-dev_web /vol -mindepth 1 -delete
  ```
- Configure dev's compose stack to mount the SQL in
- Start the DB container, wait for the import to complete, and shut it down
- Remove the SQL override
- Start the stack via systemd (see [Running under systemd](#running-under-systemd))

### Sessions and cookies

For us, dev is a subdomain of prod, and OJS scopes its session cookie to the
whole domain, so browsers send prod's session cookie to dev as well:

- Dev and prod need different `OJS_SESSION_COOKIE_NAME` values. Otherwise the
  browser sends two session cookies, OJS reads prod's, and logins on dev
  silently fail: the login works, and the next page sends you back to the
  login form. It defaults to the compose project name, which already differs,
  and prod sets it to "OJSSID".
- Prod's sessions mustn't reach dev's database, or a prod session cookie logs
  you in on dev too. That's why the data dump skips the sessions table. If dev
  ends up with prod's sessions anyway (e.g., from an older dump), empty the
  table:

  ```bash
  podman compose exec db sh -c 'mariadb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "TRUNCATE sessions"'
  ```

### Mirroring plugins

Mirror the plugins volume too, so dev gets prod's non-core plugins. To test an
upgrade on dev, follow [Upgrading a site](#upgrading-a-site), which resets the
volume to the new image's plugins. Don't just start the new image on the
mirrored volume: it would keep prod's copies of the *old* core plugins, since
OJS keeps core and non-core plugins in the same directory.

## Development

*("Development" in this case means running OJS locally, not doing work on the
OJS project itself.)*

Local development is currently just for standing up an empty OJS site just to
prepare for production. Once we're in production we'll likely alter this a lot
so that local dev is useful for testing out prod data with new themes, plugins,
etc.

### Mirroring production locally

There are scripts to help copy data through ssh from inside running containers:
`docker/mirror.sh` (for SQL) and `docker/rsync-from-prod.sh` (for volumes).
They're not getting documented here for the moment, just read the scripts. They
need a rename and maybe a merge, they're a bit confusing, but they get you SQL
data and volume exports.

Production volumes are *huge*, so be prepared for a slow mirror the first time.
If you keep the data long-term, though, subsequent mirrors are faster since we
use rsync.

Don't just set up your compose stack to use all the mirrored volumes directly!
The public and private files are probably fine to use, but prod's config will
definitely not work in local dev, and mirrored plugins need special handling in
an upgrade (see [Upgrading a site](#upgrading-a-site)).

### Setting up admins

Multiple scripts are in this repo to help automate tasks, both in production
and local development. For development you will probably need to change a
password and give somebody admin for testing things out. It's easy!

```bash
# This probably needs to be adjusted for your environment
export DSN="ojs:ojs@tcp(127.0.0.1:3306)/ojs"
make
./bin/create-admin jechols@uoregon.edu
./bin/change-password -email jechols@uoregon.edu -password adm
```

### Permissions

Permissions are a pain in OJS in dev, because you're destroying and rebuilding
volumes regularly, or needing to mirror production volumes which require
changing permissions locally, which in turn may break your in-container
permissions.

The fix: after you do anything that breaks container-level privileges,
*including rebuilding volumes*, run `docker compose exec web fixperms.sh` while
the stack is up. This can take a minute or two, but it should get all
permissions set correctly.

Run OJS's PHP tools as www-data, e.g., `docker compose exec -u www-data web
bash`. Otherwise, any files they create (e.g., in `cache/opcache`) are root's,
and Apache can't write to them until `fixperms.sh` runs again.

### Tagging in git

Tags are now going to be in the format of `v<ojs version>-<release>`, e.g.,
`v3.5.0.1-1.0.0`. Despite being really awkward, this seems like the easiest way
to make it clear what we've pushed up in terms of OJS. This is almost certainly
worth revisiting because it's a pretty awful strategy, but we need *something*.

### Email debugging

If you want to be able to debug emails, you can use the included smtpdebug
service definition (`smtpdebug.compose.yml`) in your compose stack. Along with
the compose override example's `depends_on` configuration, this would create a
service that the worker and web service both are able to use by name. Point
`.env`'s `OJS_SMTP_SERVER` at `smtpdebug` on port 25 (the `.env.example`
defaults), and then watch the logs from the smtpdebug container. This allows
you to run a dev or staging instance and see what emails would have been sent,
for instance.

Captured emails can also be browsed at `/smtp-debug-logs/`, e.g.,
`http://localhost:8080/smtp-debug-logs/`.

## Upgrading

Upgrading has two parts: updating this repo for the new OJS version, then
upgrading each site's data. Before either, read the entire [PKP OJS upgrade
guide][ojs-upgrade] and the release notes: *even build upgrades* often need
database upgrades, plugin changes, etc.

[ojs-upgrade]: <https://docs.pkp.sfu.ca/dev/upgrade-guide/en/>

### Updating the repo

This can be done in a local development instance with no risk to production or
our dev-slash-staging environment.

- Config: Look at what changed between the old and new OJS config templates,
  and carry those changes into `docker/config/config.base.inc.php`.
  `docker/config-diff.sh` handles both (it pulls the templates from PKP's
  GitHub tags):
  ```bash
  # Show what upstream changed
  ./docker/config-diff.sh 3.5.0-3 3.5.0-6

  # Merge upstream's changes into our base config, then review with "git diff"
  ./docker/config-diff.sh --merge 3.5.0-3 3.5.0-6
  ```
  - If the merge reports conflicts, resolve the markers it leaves, keeping our
    `${...}` placeholders where settings need `.env` overrides
  - Determine if new settings need to be exposed via `.env`. If so, modify
    config, modify `.env.example`, and make sure the settings are applied in
    `ojs.compose.yml`'s `x-ojs-env` section.
  - Make sure the above "Config" section is still valid.
- Image:
  - Check the PHP version with what the new OJS requires, and update
    `PHP_VERSION` in the Dockerfile if it's changed.
  - Update `OJS_VERSION` in the Dockerfile.

### Upgrading a site

Also done in dev. Get a fresh mirror of prod (see [Mirror prod to
staging](#mirror-prod-to-staging-dev)), and only upgrade prod when the dev
upgrade is good.

#### Plugins

OJS keeps gallery and uploaded plugins in the same directory as its core
plugins, so this is annoying. Then podman only copies an image's files into a
volume the first time a container mounts it, and only if it's empty (which is
good, but important to know), so a new image never updates the core plugins in
an existing volume.

When doing a build upgrade, we can generally reinstall plugins in place: back
up the volume, reset it to the new image's plugins, copy the non-core plugins
back in, and only then run OJS's upgrade tool. The upgrade only installs (and
records versions for) the plugins it finds on disk. PKP's guide has us
reinstall after the upgrade, but then the site is broken in the interim.

For a bigger upgrade, we either have to check each plugin (via [PKP's XML
plugin list][pkp-plugin-xml]) or else just follow the PKP guide and let the
site break briefly.

[pkp-plugin-xml]: <https://pkp.sfu.ca/ojs/xml/plugins.xml>

#### Steps

These examples use `ojs-prod` as the compose project name. All commands are run
as the podman user, and from the checkout location (e.g., `/srv/journals/app`).
They never read or write a volume's files through a host path, since volumes
may not be where podman says they are (see [Volume files](#volume-files)).

1. Wait for the job queue to be empty:
   ```bash
   podman compose exec -u www-data web php lib/pkp/tools/jobs.php total
   ```
2. Stop the stack, then update the checkout to the new version, since the next
   steps use its scripts. Don't build yet: that waits for the backups.
   ```bash
   systemctl --user stop "ojs@$(systemd-escape --path "$PWD")"
   ```
3. Back up the database and the plugins volume. Give MariaDB a few seconds to
   start before the dump, and make sure the dump's last line says "Dump
   completed":
   ```bash
   backup=/path/to/backups/ojs-upgrade-$(date +%F)
   mkdir -p $backup
   podman compose up -d db
   podman compose exec -T db sh -c 'mariadb-dump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' > $backup/db.sql
   tail -n1 $backup/db.sql
   ./docker/volsync.sh vol:ojs-prod_plugins $backup/plugins
   ```
   PKP's guide says to back up the private and public files too. They're huge,
   so keep those in a directory you reuse between upgrades, where rsync only
   copies what changed:
   ```bash
   mkdir -p /path/to/backups/ojs-files
   for vol in private-files public-files; do
     ./docker/volsync.sh --delete vol:ojs-prod_$vol /path/to/backups/ojs-files/$vol
   done
   ```
4. Tag the current images, so they're still around after the build replaces
   them. The plugin list (step 6) needs the old web image, and rolling back
   needs all three.
   ```bash
   for svc in web worker scheduler; do
     podman tag localhost/ojs-prod_$svc localhost/ojs-prod_$svc:pre-upgrade
   done
   ```
5. Rebuild the images (`podman compose build`). Consider pulling the latest PHP
   image first, as well as using `--no-cache` to ensure a fully clean and
   updated build.
6. List the non-core plugins to put back. The list only has plugins neither
   image has. Read the notes it prints about plugins that the new version adds
   to or drops from core.
   ```bash
   podman unshare ./docker/plugin-diff.sh --upgrade $backup/plugins image:localhost/ojs-prod_web:pre-upgrade image:localhost/ojs-prod_web > $backup/restore.txt
   cat $backup/restore.txt
   ```
   Check the list by eye, too: it assumes the volume's core plugins came from
   the image that was running. If they came from an older image (e.g., an
   earlier upgrade didn't reset the volume), any core plugins dropped since
   then show up as non-core.
7. Reset the plugins and cache volumes to the new image's files: empty each
   one, and copy in the image's copy of that directory. Don't remove and
   recreate the volumes instead, which can leave the old files in place (see
   [Volume files](#volume-files)).
   ```bash
   podman run --rm --entrypoint sh \
     -v ojs-prod_plugins:/vols/plugins -v ojs-prod_cache:/vols/cache \
     localhost/ojs-prod_web -ec '
       for d in plugins cache; do
         find /vols/$d -mindepth 1 -delete
         cp -a /var/www/html/$d/. /vols/$d/
       done'
   ```
8. For a build upgrade, you can put the non-core plugins back (bigger upgrades
   require a plugin reinstall through the gallery UI):
   ```bash
   ./docker/volsync.sh --files-from=$backup/restore.txt $backup/plugins vol:ojs-prod_plugins
   ```
9. Run OJS's upgrade tool. `check` should show the old and new versions you
   expect. The upgrade can take a while, so keep its output.
   ```bash
   podman compose run --rm -T web setpriv --reuid=www-data --regid=www-data --init-groups php tools/upgrade.php check
   podman compose run --rm -T web setpriv --reuid=www-data --regid=www-data --init-groups php tools/upgrade.php upgrade | tee $backup/upgrade.log
   ```
10. Shut down the database the steps above started, and start the stack
    through systemd:
    ```bash
    podman compose down
    systemctl --user start "ojs@$(systemd-escape --path "$PWD")"
    ```
11. Test the site with the checklist in PKP's guide ("Test the Upgrade"), and
    make sure every journal's theme loads, since most of prod's themes come
    from the gallery. To see which gallery plugins have newer releases for the
    new version (they can be upgraded from the gallery as usual):
    ```bash
    podman compose exec -u www-data web php lib/pkp/tools/plugins.php list | grep installedVersionOlder
    ```

Keep the backups and the `pre-upgrade` images until you're sure the upgrade
worked. To roll back:

- Stop the stack, check out the previous release, and tag each `pre-upgrade`
  image as `latest` again
- Load `db.sql` into an *empty* database, e.g., by emptying the db volume and
  importing, like in [Mirror prod to staging](#mirror-prod-to-staging-dev).
  Loading it over the upgraded database leaves behind the tables the upgrade
  added, which can trip up the next upgrade attempt.
- Reset the plugins and cache volumes (step 7, which now copies the old
  image's files), then copy the whole plugins backup in: `./docker/volsync.sh
  --delete $backup/plugins vol:ojs-prod_plugins`
- Shut down the database and start the stack (step 10)

## Custom OJS Work

We don't yet have a setup for doing actual OJS dev: right now the "dev" compose
example is more for running a test of the app locally and figuring out things
like settings in a safe environment.

To do development, you could clone an OJS fork and mount that into a running
container at `/var/www/html`. But be aware that will result in a really weird
local filesystem, and you'll have to do some manual work to get things up and
running. The config file will need to be rendered from the base config (or
recreated by OJS), and the public and cache directories, which are currently
volumes, will be a bit of a mess with how docker and podman manage a volume
that's mounted in as a subdirectory of another volume (your OJS code would be
the parent directory).

Ideas:

- Go back to the approach of a wholly separate prod and dev compose file,
  instead of trying to have a shared base. The prod config would define volumes
  for data we need to be able to preserve across container startups, while in
  dev there would be a single volume for everything in `/var/www/html`.
- Look into compose providers for podman that allow the `!reset` directive so
  volumes could be reset if needed, allowing dev to be volume-free if we truly
  want that, while keeping the setup more flexible.
- Provide an override example for dev which simply changes the volume targets.
  e.g., "public-files" could be `/var/local/foo` instead of
  `/var/www/html/public`, making it effectively unused.
- Don't mount the base dir at all: mount in directories that are relevant for
  editing code one at a time (e.g., `templates`, `js`, ...). Tedious, but keeps
  things consistent with how we do most compose projects. Big downside would be
  not remembering to mount something you're editing, and wondering why changes
  aren't reflected.
