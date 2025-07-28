# OJS Podman

(Technically podman or docker compose work)

This project builds a docker image for OJS v3.3.0, downloading a stable version
of their production-ready app, and providing configuration for running in
production or locally.

## Architecture / Overview

The docker image definition (`Dockerfile`) is set up to give us as much
consistency as possible across environments. No local code is copied into the
image other than "wrapper" stuff like Apache overrides, the base app
configuration template, etc.

The database needs to be initialized using the `init.sql.gz` file, or else you'll
have to run the installer, which means first modifying your OJS config directly
in the container / volume. See the config section below for details on editing
the configuration for this exact situation.

When containers are started up, because the image defines a new entrypoint,
there's a one-time step which will swap configuration variables from the
container's environment. You can define these in your compose override, and you
should do this explicitly on a per-environment basis.

*Note that this substitution happens only once*. After the first startup, your
settings can only be changed by editing the configuration file directly. This
is something we hope to improve in time, but it becomes tricky as there are
cases where the file needs to be edited manually, and those edits need to be
preserved.

The "config" volume looks weird, but is done this way in order to keep the
config totally separated from the code: it starts as an empty directory, and on
first run gets the variable-replaced configuration file added to it. That file
is then symlinked into the running container's OJS code directory. This allows
OJS to read the file, while it lives in a totally isolated volume, making
backing up and restoring easier, as well as mounting it for editing.

## Setup

### Compose

We've set up our compose files to reflect the complexity of needing to combine
services with overrides on a per-service basis, relying heavily on the compose
spec's "include" directive. This approach makes it easier to set up systems
that rely on the same base services, but have small tweaks per environment.

**Major caveat, though**: it turns out some versions (maybe most?) of
podman-compose do *not* support the "include" directive! If using podman,
you'll want to either set up the compose files manually, or use `docker compose
config -f ...` to have a flat compose setup generated for you.

To use compose, you must set up a compose.yml *and* any overrides you want for
a given environment. We provide a [compose.yml example][2], which is just a
very simple setup for combining the OJS and DB service definitions. There's
also an [example compose override][3] for specifying per-environment settings
if you want to have a base `compose.yml` that defines a core setup you reuse
across environments.

**Read the override example carefully!** Adjust settings as needed for your
environment. The various environment variables should be fairly obvious, but
they essentially just replace values in the config file, as mentioned above.

We strongly recommend familiarizing yourself not only with the [compose
spec][1], but also with the details of [using multiple compose files][4].
Understanding `include` and `extend`, how overrides work, what merging does,
etc. can be critical to making your project work well across environments.

[1]: <https://docs.docker.com/reference/compose-file/>
[2]: <compose-example.yml>
[3]: <compose.override-example.yml>
[4]: <https://docs.docker.com/compose/how-tos/multiple-compose-files/>

### Gotchas

#### You have to kill the config volume sometimes

When the config doesn't get set up properly the first time, you might go and
change the environment vars and restart the stack, then wonder why your config
is *still broken*.

As mentioned previously, config variable replacements only happen once. If you
need to fix config, you have to enter the container and edit it manually or
else destroy the volume and let it be recreated.

This should go without saying, but it's easy to forget the config situation. Or
so I hear. Obviously *I* wouldn't forget.

#### Valid app key warning

>  [WARNING] A valid APP Key already set in the config file. To overwrite, pass
>            the flag --force with the command.

Ignore this. It's just letting you know the container's config is already set
up with an app key.

#### Internal server error when you have multiple `allowed_hosts`

If you need multiple values for `allowed_hosts`, make sure you keep your YAML
formatting exactly like the compose override example we provide. For some
reason, when you have multiple allowed hosts, you *have* to make sure OJS gets
a quoted value. This means more quotes than you expect, and escaping of quotes
within quotes....

Because of how YAML interprets quoted values, `foo: 'bar'` results in `foo`
being set to three characters, `bar`, and the surrounding quotes are "lost".
When we replace this in a config file, we get something like `foo = bar` rather
than `foo = 'bar'`. To ensure you keep the single quotes, you have to "double
quote" the value in yaml, e.g., `foo: "'bar'"`.

For some reason, OJS expects a quoted value for `allowed_hosts` *even though it
works fine when allowed hosts is a single element*. So while `allowed_hosts =
["localhost"]` is fine, `allowed_hosts = ["localhost", "127.0.0.1"]` is not.
You have to have the final config setup look like `allowed_hosts =
'["localhost", "127.0.0.1"]'`.

If you get an internal server error that makes no sense, check the logs. If you
see something like `TypeError: array_map(): Argument #2 ($array) must be of
type array` or the error is from a host check (e.g., seeing
`lib/pkp/classes/security/authorization/AllowedHostsPolicy.php` in the
message), you probably need to carefully re-check the environment setting in
your compose override.

### Modifying Config

You should usually be able to set your compose environment variables, which
then get injected into the config file, and not have to edit config manually.

However, there are cases where direct config edits are necessary. In these
situations, your best bet is either an in-container edit (e.g., with `sed`), or
copying config out of the volume, editing it, and then copying it back in.

If you want to use the web installer rather than the included `init.sql.gz`
(for production you may not want to our "admin" user): start the stack, edit
the in-container config to specify `installed = Off`, then browse to the app.
The web installer will let you create a new user and set up various
configuration values. Note that you'll have to edit the configuration manually
a second time, or else change the in-container permission setup. For security
we make the config file read-only.

### Web

Start up the "web" container and browse to the login page (`/index/login`). If
you used the init SQL, log in as "admin" with password "admin", and immediately
**change your password**.

### Development

*("Development" in this case means running OJS locally, not doing work on the
OJS project itself.)*

Local development is currently just for standing up an empty OJS site just to
prepare for production. Once we're in production we'll likely alter this a lot
so that local dev is useful for testing out prod data with new themes, plugins,
etc.

#### Upgrading

Upgrading OJS is a bit trickier than it sounds if the purpose of the upgrade is
to get this repository onto a new version of OJS. (If you're upgrading a
production setup, that's a very different process, and not yet documented
here). This repo must always be usable as a new, empty OJS instance that can be
started up with minimal fuss, and reflects the latest LTS version of OJS.

To do an upgrade, there are several manual steps to take:

- Config:
  - Copy the *unmodified* config template from the new version over the top of
    `docker/config/config-template.ini`. Do not modify this file yet.
  - Add and commit in the unmodified config file so that it's easy to see
    exactly what config looked like at the start of the upgrade.
  - Look briefly over the changes so you have an idea what might have to happen
    to our docker setup once we're done installing.
  - Again: **do not** modify this config file *in any way*!
- Container / image reset:
  - Check the PHP version with what the new OJS requires. Modify the Docker
    `FROM` line if it's changed.
  - Modify the `curl` line in the Dockerfile to pull the updated OJS tarball.
  - Rebuild the docker image (e.g., `podman compose build`). Consider pulling
    the latest PHP image first, as well as using `--no-cache` to ensure a fully
    clean and updated build.
  - If you're mounting `init.sql.gz` into the mariadb container, undo that
    temporarily. We want a clean database so we can provide a new init.sql.
  - Remove your current dev volumes, e.g., `podman compose down -v`.
- Start the stack and make the config file writeable:
  - `podman compose up -d web`
  - `podman compose exec web bash`
  - `chmod 777 /var/local/config/config.inc.php`
  - *The installer will claim this is optional, but on some OJS versions, it is
    definitely required.*
- Web install:
  - Visit the app URL. The installation screen should show up.
  - Settings:
    - Set administrator to "admin" with password "admin".
    - Use a dummy email like `admin@example.org`.
    - Ignore locales and timezone.
    - Change upload location to `/var/local/ojs-files`.
    - Database settings (assuming you are using `db.compose.yml`):
      - Host: `db`
      - Username: `ojs`
      - Password: `ojs`
      - Database name: `ojs`
  - Disable "Beacon".
  - Press the install button. Wait a bit. There may not be any indication that
    it's working, but it is.
  - If all goes well, you'll see a success page. If it doesn't, you're in for a
    fun day of debugging! The app won't log errors beyond whatever causes PHP
    to crash. Enjoy!
- Get the new config file into the repo:
  - Copy the file out of the container, e.g., `docker compose exec web cat
    /var/local/config/config.inc.php > docker/config/config-template.ini`
  - Look over the changes to make sure everything looks good. No major changes
    should have happened, since the installer should only be setting up values,
    not adding/removing keys.
  - Now start the process of re-setting things to allow for variable
    replacements. This can be a pain: you need to understand what changed from
    one version to the next, as well as what config settings we will want to
    make configurable in the compose setup.
    - Compare the previous version's base config with the new version to see
      what's changed.
    - In some cases a setting is no longer needed, and the compose files should
      be adjusted. In some cases a new setting may be needed.
  - If we're in production, we'll need to document a strategy for migrating the
    config file. This is still a big unknown, but it will be critical to figure
    out once we do our first post-go-live upgrade.
  - Add and commit the updated config file. Do *not* merge this commit with the
    above commit. We should always be able to see the difference between two
    OJS versions' vanilla configs as well as the difference between the vanilla
    config and our modifications.
- Generate a new `init.sql.gz` file:
  - `mysqldump -h127.0.0.1 -uojs -pojs ojs | gz -9 > docker/init.sql.gz`
- Restart things to verify:
  - Take down the stack, and delete all volumes so you can test a fresh stack.
    Make sure you do this *only after* you've exported the SQL!
  - Re-add `init.sql.gz` to your compose override so your db will be
    initialized when you restart.
  - Rebuild the docker image now that you have the config and SQL updated,
    otherwise you'll probably waste two hours trying to figure out why you did
    all the things above and nothing works. Or so I've heard.
  - Start up the stack. You should be able to log into things as normal.

**Important!** As mentioned above, *make sure you understand* any new or
changed settings! This is really *really* important. For instance in 3.5,
`app_key` was added, and it appeared that we would want to make it adjustable.
After looking at how a new install sets it up, though, and digging a bit in the
code, we discovered that this is a setting users shouldn't be manually setting
unless they really know what they're doing. This meant we had to find a way to
get it set as if you were doing a new install, but without having to do that.
Which meant adding some complexity to the init part of the entrypoint, learning
about some tools in the OJS codebase, etc.

**Note 1**: this process is for upgrading OJS *in this repo*. Production
updates might be similar, *but we do not know. They may be completely different
in ways we can't even guess right now*. Until we have a production setup to
upgrade, this documentation won't cover that scenario.

**Note 2**: the easiest way to get the new config template is probably grabbing
the raw file from github. e.g.:

```
curl https://raw.githubusercontent.com/pkp/ojs/refs/tags/3_5_0-1/config.TEMPLATE.inc.php \
     > docker/config/config-template.ini
```

### Custom OJS Work

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
