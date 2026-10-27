# Container logs

*Paths below use `/path/to/ojs` in place of the real directory.*

Every service writes its stdout/stderr to its own file in `CONTAINER_LOG_DIR`:
`web.log`, `worker.log`, `proxy.log`, etc. These are podman's normal
`k8s-file` logs, just kept somewhere stable instead of in each container's
storage.

What ends up where:

- `web.log`: Apache's access and error logs, which includes PHP / OJS errors
- `worker.log`: OJS's job runner
- `proxy.log`: Caddy's access log, plus Caddy's own messages
- `tps.log`, `db.log`, `smtpdebug.log`: what you'd expect

Why not podman's defaults?

- Podman keeps `k8s-file` logs inside the container's storage, so they're
  deleted along with the container: any `down`, or any time compose recreates
  it (e.g., `up -d` after a `.env` change).
- The `journald` driver needs per-user journals, which a rootless podman user
  only gets with persistent journal storage and a non-system UID. Without
  those, the user can't read the logs (and `podman logs` fails). Fixing that is
  a system-wide journald change we'd rather avoid.

## Setup

Set `CONTAINER_LOG_DIR` in `.env`. Two hard rules:

- It must be absolute: podman stores a relative path as-is and resolves it
  against whatever directory podman runs from later, so `podman logs` or a
  restart from somewhere else reads or writes the wrong file. You can use
  `${PWD}/...` in place of `./...`.
- It must already exist, otherwise conmon can't open the file and the container
  won't start (`conmon failed: exit status 1`).

In production, use a directory outside the checkout, e.g.:

```bash
mkdir /path/to/ojs-logs
```

Dev should use the `.env.example` value, `${PWD}/logs` (it's in `.gitignore`).

## Reading logs

- `podman logs` and `podman compose logs` still work. One quirk: a recreated
  container's `podman logs` also shows older containers' output, since it
  reads the whole file.
- Or read the files directly. Each line is
  `<timestamp> <stdout|stderr> <F|P> <message>`, where `P` means a partial line
  continued on the next one.

## Rotation

On dev, just delete files as needed. In prod, the podman user needs a logrotate
config and cron job. e.g., `/path/to/ojs/logrotate.conf`:

```
/path/to/ojs-logs/*.log {
  daily
  maxsize 100M
  rotate 30
  missingok
  notifempty
  copytruncate
  compress
}
```

And an hourly cron job, e.g., in `/etc/cron.d/ojs-logrotate` (replace
`<podman user>` with the user that runs the stack):

```
0 * * * *	<podman user>	/usr/sbin/logrotate -s /path/to/ojs/logrotate.status /path/to/ojs/logrotate.conf
```

Notes:

- **Keep the `daily`** (or another interval). Without one, logrotate uses its
  default of rotating at 1 MiB, and `maxsize` never kicks in: `maxsize` only
  rotates *sooner* than the interval would. With an hourly cron, this config
  rotates once a day, or sooner if a file passes 100M.
- `copytruncate` is safe here: conmon opens the file for appending, so after a
  truncate it writes from the start, with no gap of null bytes. A few lines
  written between the copy and the truncate can be lost.
- Don't also set podman's `log_size_max` (`containers.conf`) or a `max-size`
  log option. When a file hits that size, conmon just empties it, which fights
  logrotate and loses the history.
