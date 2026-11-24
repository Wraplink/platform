# Production backup and restore

Backups include a PostgreSQL custom-format logical dump, the `mailqueue`, `mailkeys`, and `dnsqueryspool` Docker named volumes, generated non-secret platform configuration, and optional Let's Encrypt files. The `.env` secrets file is deliberately excluded; back it up separately in a secure secrets store. Edge nodes and external storage are not included.

## Install on Debian 13

Run from the central production host (assumes checkout at `/home/wraplink/platform`):

```bash
sudo install -m 0644 systemd/wraplink-backup.service /etc/systemd/system/
sudo install -m 0644 systemd/wraplink-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wraplink-backup.timer
sudo systemctl start wraplink-backup.service
sudo systemctl status wraplink-backup.service
sudo systemctl list-timers wraplink-backup.timer
```

Default backup directory: `/var/backups/wraplink`. Configure `WRAPLINK_BACKUP_DIR` and `WRAPLINK_BACKUP_RETENTION_DAYS` in `.env`. Daily schedule is 03:00 Asia/Tehran, with missed runs caught up after reboot. Root-only directory permissions are recommended.

## Restore

First make an independent copy of current data. Ensure enough disk space and schedule downtime. Restore is destructive and **does not automatically restart services**.

```bash
sudo bash scripts/restore.sh /var/backups/wraplink/20261124T000000Z
```

Replace the example ID with a real backup directory. The script checks SHA-256 hashes, asks for explicit confirmation, stops application writers, restores PostgreSQL, then restores selected volumes. Review `platform-config.tar.gz`, `letsencrypt.tar.gz`, and `certbot.tar.gz` manually; they are not automatically overwritten. Restore `.env` separately from your secrets store, then deploy normally.

**Limitations:** Named volume identifiers assume Compose project name `wraplink`. Volume tar archives are not transactional while services are running, so mail queue and DNS spool may be inconsistent. For strict consistency, pause mail and DNS writers during the volume snapshot or back them up in a maintenance window. The database dump itself is transactionally consistent. Backup files on the same host do not protect against host failure: replicate encrypted copies to an off-host destination and test recovery regularly. Keep retention appropriate to legal and operational requirements.
