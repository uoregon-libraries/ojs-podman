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

The database needs to be initialized using the `init.sql` file, or else you'll
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

### Modifying Config

You should usually be able to set your compose environment variables, which
then get injected into the config file, and not have to edit config manually.

However, there are cases where direct config edits are necessary. In these
situations, your best bet is either an in-container edit (e.g., with `sed`), or
copying config out of the volume, editing it, and then copying it back in.

If you want to use the web installer rather than the included `init.sql` (for
production you may not want to our "admin" user): start the stack, edit the
in-container config to specify `installed = Off`, then browse to the app. The
web installer will let you create a new user and set up various configuration
values. Note that you'll have to edit the configuration manually a second time,
or else change the in-container permission setup. For security we make the
config file read-only.

### Web

Start up the "web" container and browse to the login page (`/index/login`). If
you used the init SQL, log in as "admin" with password "admin", and immediately
**change your password**.

### Development

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
