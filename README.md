# OJS Podman

(Technically podman or docker compose work)

This project builds a docker image for OJS, downloading a stable version of
their production-ready app, and providing configuration for running in
production or locally.

## Architecture / Overview

The docker image definition (`Dockerfile`) is set up to give us as much
consistency as possible across environments. No local code is copied into the
image other than "wrapper" stuff like Apache overrides, entrypoint script, etc.

The "config" volume looks weird, but is done this way in order to keep the
config totally separated from the code: it starts as an empty directory, and on
first run gets our base config file added to it. On startup, the
entrypoint copies that file into OJS's code directory, filling in values from
the environment (see [Config](#config)). The real file lives in a totally
isolated volume, making backing up and restoring easier, as well as mounting it
for editing.

Requests pass through a few services before reaching OJS:

- **proxy** (Caddy) is the reverse-proxy in front of the whole stack
- **tps** ([Turnstile Proxy Server][tps]) blocks some form submissions until
  people pass a Cloudflare Turnstile challenge
- **web** is Apache + PHP running OJS
  - Never expose this directly: bots can then skip TPS entirely

[tps]: <https://github.com/uoregon-libraries/turnstile-proxy-server>

Note: if a proxy with a public IP address fronts the stack (e.g., HAProxy),
list it in `.env`'s `EXTRA_TRUSTED_PROXIES`. Otherwise the whole
stack reports the wrong IP address.

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

The first time you start the "web" container, our base config
(`docker/config/config.base.inc.php`) is copied into the config volume. It's
OJS's config template, set up for this stack:

- Settings that change per environment (URLs, allowed hosts, database,
  secrets, mail server, OAI repository ID) are filled in from `.env` (see
  [Placeholders](#placeholders)). Most of the URL-related ones are built from
  `PUBLIC_SCHEME`, `PUBLIC_HOST`, and `PUBLIC_PORT_SUFFIX`.
- Settings the stack depends on are already set: `files_dir` is
  `/var/local/ojs-files`, `restful_urls` and `trust_x_forwarded_for` are On,
  mail goes out over SMTP, and `job_runner` is Off, since the "worker" service
  runs jobs
- Settings that are the same in every environment match our production site,
  e.g., `time_zone` and `enable_beacon`

So you shouldn't need to edit the config to get a site running.

Once it's in the volume, the config is yours: rebuilding the image doesn't
change it, and changes to the base config only reach new sites. To edit it,
mount the config volume somewhere temporarily, or copy the config out of the
volume, edit it, and copy it back in.

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

- The vars come from `.env`, but only the ones `ojs.compose.yml` passes to
  the container: the `MYSQL_` vars, and some `PUBLIC_` and `OJS_` ones. To add
  one, add it there and to `.env.example`.
- The exception is `HTTPS`, which the entrypoint sets to "on" or "off" from
  `PUBLIC_SCHEME`. It also passes that to OJS, along with the public port,
  since OJS can't tell either one from behind our proxies.
- Put text in quotes. Leave on/off settings and numbers unquoted: OJS reads a
  quoted "Off" as text, which counts as *on*.
- If the config uses a var that's blank or unset, the container won't start,
  and its log says what's missing.

OJS reads a copy of the config, which is read-only and only made at startup.
So **after editing the config, restart web and worker**.

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
- Copy the old config's `app_key`, `salt`, and `api_key_secret` into `.env`.
  If it doesn't have an app key (older OJS versions don't), generate one (see
  `.env.example`).
- Set `OJS_OAI_REPOSITORY_ID` to the old config's `repository_id`, which must
  never change on a live site
- Copy anything else the old site customized into the new config

You can use the old config instead of the base config, but OJS won't use
`.env` until you swap the config's values for placeholders. Either way, diff it
against the base config to catch the settings this stack depends on.

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

## Mirror prod to staging ("dev")

*Our "dev" site isn't really dev, but we named it that, so we're stuck with it.*

Mirroring data from production to dev is easiest done on the container host via
rsync and SQL exports.

```bash
# (ssh into the server as the podman user)

# Get into podman's volume dir
cd ~/.local/share/containers/storage/volumes/

# Make sure all commands are run inside podman's rootless user namespace -
# without this, you're going to get permissions problems running the rsync
# and/or starting up dev
podman unshare

# Mirror raw files
rsync -avzP --exclude="usageStats/archive/" --exclude="temp/" --delete ojs-prod_private-files/ ojs-dev_private-files/
rsync -avzP --delete ojs-prod_public-files/ ojs-dev_public-files/

# You might not want to do this one! See docs below.
rsync -avzP --delete ojs-prod_plugins/ ojs-dev_plugins/
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
export devpath=/path/to/ojs/dev
/usr/local/bin/podman-mysqldump.sh ojs-prod web -hdb -d ojs > $devpath/exports/db/001-struct.sql
/usr/local/bin/podman-mysqldump.sh ojs-prod web -hdb -t ojs > $devpath/exports/db/002-data.sql
```

Then:

- Delete the dev db volume, e.g., `podman volume rm ojs-dev_db`
- Configure dev's compose stack to mount the SQL in
- Start the DB container, wait for the import to complete, and shut it down
- Remove the SQL override
- Start the stack via systemd

### Do *not* mirror plugins for upgrading!

If the purpose is to test an upgrade, the plugin volume should *not* be
mirrored, and may in fact need to be destroyed manually since podman volumes
are only populated with image data if they're empty ("copy up").

Why do we need this? OJS upgrades, even when they claim "No breaking changes,"
can alter the core plugins. Which sit in the **same directory as custom
plugins**. So we have to reinstall plugins on top of core rather than just
doing a plugin backup and restore.

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
definitely not work in local dev, and you occasionally don't want to use the
mirrored plugins (e.g., in an upgrade situation).

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

### Upgrading

To do an upgrade, there are several manual steps to take:

- Config: Look at all differences from the old config template to the new,
  and apply them to `docker/config/config.base.inc.php` (including the version
  in its header). Existing sites' configs don't change on their own. Make sure
  the above "Config" section is updated.
- Container / image reset:
  - Check the PHP version with what the new OJS requires. Modify the Docker
    `FROM` line if it's changed.
  - Modify the `curl` line in the Dockerfile to pull the updated OJS tarball.
  - Rebuild the docker image (e.g., `podman compose build`). Consider pulling
    the latest PHP image first, as well as using `--no-cache` to ensure a fully
    clean and updated build.
  - Delete all volumes. Remember this is for *dev upgrades*, **not**
    production!
- Do the web install (see [New site](#new-site)) and you should be set.

**Note**: this process is for upgrading OJS *in this repo*. Production updates
might be similar, *but we do not know. They may be completely different in ways
we can't even guess right now*. Until we have a production setup to upgrade,
this documentation won't cover that scenario.

## Custom OJS Work

We don't yet have a setup for doing actual OJS dev: right now the "dev" compose
example is more for running a test of the app locally and figuring out things
like settings in a safe environment.

To do development, you could clone an OJS fork and mount that into a running
container at `/var/www/html`. But be aware that will result in a really weird
local filesystem, and you'll have to do some manual work to get things up and
running. The config file will need to be copied out of its volume (or recreated
by OJS), and the public and cache directories, which are currently volumes,
will be a bit of a mess with how docker and podman manage a volume that's
mounted in as a subdirectory of another volume (your OJS code would be the
parent directory).

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
