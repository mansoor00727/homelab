# Migrating the stack to new hardware

Goal: move every service and its data to a new machine with no data loss, then take over the old
machine's IP address so DNS rewrites, bookmarks and dashboards keep working.

## 0. Prepare the new host
1. Install the OS (see `autoinstall-user-data.example`) and Docker.
2. Create `/opt/stack` and copy the compose files in from `compose/`.
3. Free port 53 for AdGuard (disable the systemd-resolved stub listener).
4. Apply any hardware quirks the data drive needs *before* attaching it
   (`usbcore.autosuspend=-1 usb-storage.quirks=<vid:pid>:u` in GRUB).

## 1. Freeze the old host
1. Dump the photo database:
   `docker exec immich_postgres pg_dumpall --clean --if-exists --username=postgres | gzip > immich-db.sql.gz`
2. Set containers to not auto-restart (`docker update --restart=no <names>`) and stop them.
3. Archive configs and app data onto the data drive:
   `sudo tar --numeric-owner -cpf /srv/data/migration/opt-data.tar -C / opt/appdata/... opt/immich opt/adguard`
4. Check the archive (`ls -lh`, `tar -tf ... | wc -l`), `sync`, power off.

## 2. Move the data
1. Move the drive to the new host. Add its UUID to `/etc/fstab` with `nofail,x-systemd.device-timeout=30`
   so a missing drive can never block boot.
2. `sudo tar --numeric-owner -xpf /srv/data/migration/opt-data.tar -C /`

## 3. Start in dependency order
1. AdGuard first (DNS), then the main stack, then Immich.
2. Verify with `scripts/healthcheck.sh`.

## 4. Take over the old IP
Add the old address next to the DHCP one first (so your SSH session survives), confirm it works from
a second terminal, then switch to a static config with netplan. Clear stale SSH host keys on your
clients (`ssh-keygen -R <ip>`) after confirming the new fingerprint matches.

## 5. Remote access
Install Tailscale on the new host as a new node, update the DNS record that points at the tailnet
address, delete the old node, and disable key expiry on the server.

## Lessons
- Verify before you delete: keep the old machine intact until the new one has run cleanly for a while.
- Check which machine your terminal is on before running a destructive or stateful command.
- Treat the migration as an ordering problem.
