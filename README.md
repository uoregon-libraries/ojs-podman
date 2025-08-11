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

### Development

*("Development" in this case means running OJS locally, not doing work on the
OJS project itself.)*

Local development is currently just for standing up an empty OJS site just to
prepare for production. Once we're in production we'll likely alter this a lot
so that local dev is useful for testing out prod data with new themes, plugins,
etc.

#### Tagging in git

Tags are now going to be in the format of `<ojs version>_<release>`, e.g.,
`3.5.0-1_1.0.0`. Despite being really awkward, this seems like the easiest way
to make it clear what we've pushed up in terms of OJS. This is almost certainly
worth revisiting because it's a pretty awful strategy, but we need *something*.

#### Upgrading

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

### Migrating old data

These instructions are for doing your migration *in dev, using podman for both
current prod and next-prod*. We have no plans to document any other process.

Get backups of your production server's private files, public files, and
database. If production is in podman, you can just down the services and copy
the publie/private files' volumes directly. The DB should be dumped with
`mysqldump` as raw file copies will occasionally give you very hard-to-debug
problems. If production is not in podman, you will need to copy the files more
manually, but the overall process will be very similar.

Note that you'll probably want *two* database dumps. One original untouched
from the server, and one that you hack things into. Many errors can require
re-importing data after fixing something, and you don't want to have to
remember to re-fix multiple database problems.

#### Prep

- Create two overrides for your compose setup: a "current" one and a "next"
  one. In each one you need to set up explicit compose names, docker image
  names, and build args.
  - Compose name is a top-level identifier which determines the names of
    volumes, containers, etc. You need to have different names to avoid
    collisions between the two stacks.
  - Build args will change the docker image you build so it's got the current /
    next PHP and OJS versions.
  - Image names are critical to ensure a stack is using its custom image and
    not the base image.
  - The override example has all these fields in it, but build args are
    commented out since you usually won't need to customize them.
- Make sure you pay close attention when running commands, as you'll need to
  specify all files in your compose configuration chain. It's probably worth
  aliasing commands for each setup (e.g., `alias pc-current='podman compose -f
  compose.yml -f current.override.yml'`)
- If necessary, update the `Dockerfile` to install any package that either
  version of OJS needs. You don't want to be trying to manage two different
  Dockerfiles in addition to the rest of the migration.
- Consider creating a broken `compose.override.yml` so that you can't
  accidentally run the stack normally.

#### Import production into "current"

- Start the stack, e.g., `podman compose -f compose.yml -f current.compose.yml
  up -d web`.
- Import the DB dump into the "db" container.
  - **You need an admin user.** If you scrub admins from the DB for any reason,
    you need to create one! See notes below in the "Migration Fixes" section.
  - If you get something like `Got error 1 "Operation not permitted" during
    COMMIT`, you may have to hack up the production database dump. I haven't
    been able to figure out how to get around this without *removing* `INSERT`
    statements from the `submission_search_keyword_list` table. I suspect it's
    due to different versions and settings from current prod to new prod, but
    we needed to just get this done after trying in vain to get settings fixed.
    We're *fairly* certain that table isn't used in newer OJS versions....
- Copy your production files into the container's volumes. This might mean
  installing rsync into the image and mounting the source volumes temporarily,
  copying files directly into the podman volume directory on the host and then
  changing permissions manually, etc.
- Get your production config file copied and modify it as needed. e.g., you
  might need to change things like `allowed_hosts`.
- Fix ownership and permissions for various files and directories.
  - `chown -R www-data:www-data /var/local/ojs-files /var/www/html/cache /var/www/html/public /var/www/html/plugins`
  - `chown www-data /var/local/config/config.inc.php && chmod 400 /var/local/config/config.inc.php`
- Test that the setup is running and your local server looks like production.
  - This piece can be *crucial* to the migration, don't skip it! It may be
    necessary to run scheduled jobs in some setups, and hitting the website is
    one of the common ways this happens. **Don't skip this step**! Log in as an
    admin, even, to make *everything* seems to work.
- Get a diff between the config template and your actual config. This can be
  done by copying the template out of a running container, then just running
  `diff`. You will need to save this so you know which settings actually differ
  from the defaults.
- Take down the stack, but **do not delete volumes**!

#### Prepare the new stack

- Create the services without starting them so that the volumes get
  initialized. e.g., `podman compose -f compose.yml -f next.compose.yml up
  --no-start`.
- Mirror the files and db volumes from "current" to "next". The easiest way to
  do this is simply rsync the raw files on the host. See Note 1 under
  "Migration Fixes" for an example.
- Start the stack, e.g., `podman compose -f compose.yml -f next.compose.yml up
  -d web`. Don't hit the web endpoint yet!
- The config file will have been copied from its template in the new OJS
  version. Modify this file (copy out of the container, edit, copy back in; or
  edit it directly from the host's `ojs-next_config` volume) based on the diff
  you created above.
- Fix ownership and permissions for various files and directories.
  - `chown -R www-data:www-data /var/local/ojs-files /var/www/html/cache /var/www/html/public /var/www/html/plugins`
  - `chown www-data /var/local/config/config.inc.php && chmod 400 /var/local/config/config.inc.php`
- Run the OJS CLI upgrade tool, e.g., enter the web container a run `php
  tools/upgrade.php check` and if all is well, run the upgrade *with a lot of
  RAM*, e.g., `php -d memory_limit=4096M tools/upgrade.php upgrade`
  - If you didn't create an admin user in the "current" stack's DB import, this
    *will fail with no explanation and just a usage message*. You will be very
    confused. Make sure you have an admin!
  - If you have busted logs, you may have to restart from the "current" stack
    because the logs have to be repaired in the same version where they failed.
    Note that the fix "should" be running a task scheduler, but in some cases
    you cannot run the PHP command-line task tool! Logging into the "current"
    site may be required to get tasks to run.
  - If journals are missing contact info, the easiest approach is to edit the
    database. More info in "Migration Fixes" below.
  - If you have other errors, it's usually the case that you'll have to fix the
    problems in "current", then start over again. "next" won't run properly
    until it's upgraded, at least in the cases we run into. So if you get error
    messages that seem easy to fix, keep in mind you still have to fix them in
    "current".

Note that when failures occur, you often have to restart the process, which
often means having to re-mirror "current" to "next". In most cases *you do not
want to delete volumes!*. Usually you can use rsync to ensure the DB and file
volumes are back to their pre-migration state, which is significantly faster
than deleting the volumes and re-copying every file.

- **TODO** more?

- Visit the local homepage

#### Migration Fixes

##### Mirroring via rsync

If you're using podman, mirroring your "current" OJS is a lot easier to do
using `rsync` rather than exporting things via any OJS process. You can script
it with done something like this (note that this only echoes the commands to
use, doesn't actually run them):

```bash
cd ~/.local/share/containers/storage/volumes/
for svc in public-files private-files db; do
  echo "rsync -a --delete ojs-current_$svc/ ojs-next_$svc/"
done
```

##### Adding an admin user

Make sure there's an admin user in the database! If there isn't,
you'll get a usage message from the "upgrade" tool that just tells you the
commands it supports. There will be *no explanation* that you need an admin
user. If this happens (e.g., you remove admin privs in production, or scrub
admins automatically in exported data or something), you'll have to manually
insert an admin user.

The "easy" fix is to create yet another namespaced override, copying "current"
(compose setup only, not files or db) so the database schema matches your
production schema. Start that stack and do the web install. Then export the
`users` table and you'll have an `INSERT` statement you can use in your
"current" db.

For instance, an admin with the password "admin" in 3.3.0-8 can be created with
the following SQL:

```sql
INSERT INTO `users` VALUES (1,'admin','$2y$10$F82pubB1MFZratL.a/zF0OVRUFE6GT8.GKg8O.KBXboDWFpPcLiR6','admin@example.org',NULL,NULL,NULL,NULL,NULL,'',NULL,NULL,'2025-08-05 22:18:32',NULL,'2025-08-05 22:18:32',0,NULL,NULL,0,NULL,1);
```

Add the SQL to a copy of your production DB export so that a full restart
prevents future failures.

##### Missing Journal Contact Information

Similar to missing admin users, this is fixed most easily (and repeatably) by
fixing the problem once, exporting SQL, and putting the fix into your SQL dump
so it persistent when things fail again.

First, stand up your "current" stack again and reload the database so it has
your prod (plus fixes) data. Then export all `journal_settings` for the journal
in question, one insert per line:

```
mysqldump -uroot -proot_password -h127.0.0.1 ojs journal_settings \
          --no-create-info --skip-extended-insert --where="journal_id=1" \
          > journal_settings_export.sql
```

If you don't have it, you can find the id by examining the `journals` table's
`journal_id` field.

Next, you'll need to log in to the app as admin and browse to the journal's
settings page, e.g., `http://localhost:8080/<abbrev>/management/settings/context`.
Create the contact info and save it.

Finally you'll export the journal settings again, this time to new file so you
can look at the differences. The new settings should be obvious, and you can
copy those into your "current" db dump (so that future import restarts aren't
hindered by this error).

Example SQL for only the required fields:

```sql
INSERT INTO `journal_settings` VALUES (1,'','contactEmail','contactemail@example.org',NULL);
INSERT INTO `journal_settings` VALUES (1,'','contactName','ContactName',NULL);
INSERT INTO `journal_settings` VALUES (1,'','mailingAddress','123 Mailing Address Way',NULL);
INSERT INTO `journal_settings` VALUES (1,'','supportEmail','supportemail@example.org',NULL);
INSERT INTO `journal_settings` VALUES (1,'','supportName','SupportName',NULL);
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
