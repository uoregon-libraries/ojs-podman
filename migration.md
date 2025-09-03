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
  - Don't forget to get the plugins from production's *codebase*! Without
    plugins, things break badly. OJS mixes core *and external* plugins right in
    the app's source directory, so there's no easy way to mirror only your
    external plugins.
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
- **Delete** any new files in the private file mount under
  `usageStats/usageEventLogs/`! These can make the migration fail. The hostname
  in the other usage logs won't match the new usage logs where you were
  connecting to localhost, and OJS seems to hate this.
- Take down the stack, but **do not delete volumes**!

#### Prepare the new stack

- Create the services without starting them so that the volumes get
  initialized. e.g., `podman compose -f compose.yml -f next.compose.yml up
  --no-start`.
- Mirror the files and db volumes from "current" to "next". The easiest way to
  do this is simply rsync the raw files on the host. See Note 1 under
  "Migration Fixes" for an example.
  - Again, you'll need to deal with the plugins volume in a special way... but
    this time you only want to mirror the new version's core plugins. *Do not
    copy the old version's plugins directory*.
- Start the stack, e.g., `podman compose -f compose.yml -f next.compose.yml up
  -d web`. Don't hit the web endpoint yet!
- The config file will have been copied from its template in the new OJS
  version. Modify this file (copy out of the container, edit, copy back in; or
  edit it directly from the host's `ojs-next_config` volume) based on the diff
  you created above.
- Fix ownership and permissions for various files and directories.
  - `chown -R www-data:www-data /var/local/ojs-files /var/www/html/cache /var/www/html/public /var/www/html/plugins`
  - `chown www-data /var/local/config/config.inc.php && chmod 400 /var/local/config/config.inc.php`
- Make sure you delete any new usage stats! This is mentioned above, but it
  keeps biting me.
  - e.g., `rm /var/local/ojs-files/usageStats/usageEventLogs/usage_events_20250825.log`
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

##### A16 (Adding An Additional Administrative Account Anytime, Anywhere, Allowing All Authorized Administrators Ample Access And Absolute Authority)

Anytime you need to, you can create multiple admin accounts. OJS is very opaque
about this, but they mention in their FAQ that you can execute SQL to do this.
Which is nuts, but... OJS will be OJS, as they say.

Figure out the group ID you need, then associate it with a user who needs admin
access. The group id can be found via:

```sql
; Official docs say to look for a context id of 0:
SELECT user_group_id FROM user_groups WHERE context_id=0 AND role_id=1;

; ...but our admin from OJS 3.3.0-8 had a NULL id, so we did this:
SELECT user_group_id FROM user_groups WHERE context_id IS NULL AND role_id=1;
```

For us, the answer was 1. Now find the user id you want to give admin
privileges to. You'll need to know their username, but presumably you know that
if you're giving them admin....

```sql
select user_id from users where username = 'jbriggs';
```

Finally, you just need to give that user id access to the admin group:

```sql
INSERT INTO user_user_groups (user_id, user_group_id) VALUES (<user_id>, <user_group_id>);
```

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
