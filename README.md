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
first run gets the base configuration file added to it. That file is then
symlinked into the running container's OJS code directory. This allows OJS to
read the file, while it lives in a totally isolated volume, making backing up
and restoring easier, as well as mounting it for editing.

## Setup

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
very simple setup for combining the OJS and DB service definitions. There's
also an [example compose override][3] for specifying per-environment settings
if you want to have a base `compose.yml` that defines a core setup you reuse
across environments.

We strongly recommend familiarizing yourself not only with the [compose
spec][1], but also with the details of [using multiple compose files][4].
Understanding `include` and `extend`, how overrides work, what merging does,
etc. can be critical to making your project work well across environments.

[1]: <https://docs.docker.com/reference/compose-file/>
[2]: <compose-example.yml>
[3]: <compose.override-example.yml>
[4]: <https://docs.docker.com/compose/how-tos/multiple-compose-files/>

### Config

The first time you start the "web" container, a config file will be created
from the OJS config template file. If you don't modify it, you'll be presented
with the OJS web installer, which will get some basic settings written for you.
Some settings have to be set to hard-coded values for the compose setup to run:

- The "directory for uploads" must be `/var/local/ojs-files`
- Database settings should be as follows (for production you should use compose
  overrides and have a secure password, or else be 100% sure your database
  service is locked down):
  - Host: "db"
  - Username: "ojs"
  - Password: "ojs"
  - Database name: "ojs"

You generally still need to edit the config file after it's been created, as
the web installer skips a lot of critical things. You need to examine all
values carefully. Here are some settings that are confusing / not obvious they
have to be set:

- `app_key`: This is set by the web installer, but if you aren't using that
  (e.g., you're upgrading from 3.3 or something), you have to generate an app
  key via the OJS tool:
  - Start the stack
  - Enter the running "web" container
  - In the container, execute `php ./lib/pkp/tools/appKey.php generate`
- `installed`: If you don't plan to use the web installer, and will manage all
  config yourself, this must be "Off".
- `restful_urls`: You usually want this set to "On": the provided docker image
  sets up Apache to work with this setting.
- `trust_x_forwarded_for`: Should be "On" to get the proper client IP address
  through the docker stack.
- `files_dir`: The web installer calls this "directory for uploads". This
  *must* be set to `/var/local/ojs-files`. Normally the web installer will set
  this for you, but it's worth double-checking the value.
- `public_files_dir`: This *must* be set to `public`.

Editing the config file is most easily done by mounting the config volume
somewhere temporarily to edit it, or copying config out of the volume, editing
it, and then copying it back in.

## Development

*("Development" in this case means running OJS locally, not doing work on the
OJS project itself.)*

Local development is currently just for standing up an empty OJS site just to
prepare for production. Once we're in production we'll likely alter this a lot
so that local dev is useful for testing out prod data with new themes, plugins,
etc.

### Setting up admins

Multiple scripts are in this repo to help automate tasks, both in production
and local development. For development you will probably need to change a
password and give somebody admin for testing things out. It's easy!

```bash
make
./bin/create-admin jechols@uoregon.edu
./bin/change-password -email jechols@uoregon.edu -password adm
```

### Tagging in git

Tags are now going to be in the format of `v<ojs version>-<release>`, e.g.,
`v3.5.0.1-1.0.0`. Despite being really awkward, this seems like the easiest way
to make it clear what we've pushed up in terms of OJS. This is almost certainly
worth revisiting because it's a pretty awful strategy, but we need *something*.

### Email debugging

If you want to be able to debug emails, you can use the included smtpdebug
service definition (`smtpdebug.compose.yml`) in your compose stack. Along with
the compose override example's `depends_on` configuration, this would create a
service that the worker and web service both are able to use by name. You'd
configure your OJS to point to `smtpdebug` on port 25, and then watch the logs
from the smtpdebug container. This allows you to run a dev instance and see
what emails would have been sent, for instance.

### Upgrading

To do an upgrade, there are several manual steps to take:

- Config: Look at all differences from the old config template to the new. Make
  sure the above "Config" section is updated.
- Container / image reset:
  - Check the PHP version with what the new OJS requires. Modify the Docker
    `FROM` line if it's changed.
  - Modify the `curl` line in the Dockerfile to pull the updated OJS tarball.
  - Rebuild the docker image (e.g., `podman compose build`). Consider pulling
    the latest PHP image first, as well as using `--no-cache` to ensure a fully
    clean and updated build.
  - Delete all volumes. Remember this is for *dev upgrades*, **not**
    production!
- Do the web install and you should be set.

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
