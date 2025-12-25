# server-scripts

Maintenance scripts for the server: daily and weekly backups, and basic server maintenance tasks.

## What this repo contains ✅
- `daily_gamenight.sh` — daily dump of the `gamenight` MySQL database, gzips the dump, uploads to `s3://$S3_BUCKET/daily/`, and rotates local daily backups (keep 7). 🔁
- `weekly_backup.sh` — weekly gzipped dumps of the databases (`gamenight`, `microblog`, `tools`, `cozy`), uploads to `s3://$S3_BUCKET/weekly/`, rotates weekly backups (keep 2). 📦
- `weekly.sh` — weekly maintenance tasks (apt update/upgrade, Laravel cache clears, etc.). It now **delegates** DB backups to `weekly_backup.sh` and **does not reboot** unless called with `--reboot` or when `/home/ubuntu/ALLOW_REBOOT` exists. 🔧
- `trim_laravel_logs.sh` — trims Laravel logs safely (lockfile, mktemp) and logs activity to `/home/blogger/trim_laravel_logs.log`. 🧹
- `.server-scripts.conf.example` — example config; **do not** commit real credentials. 🔒

## Config & secrets (required) 🔐
1. Copy the example config to the ubuntu account and edit it:
```bash
cp .server-scripts.conf.example ~/.server-scripts.conf
chmod 600 ~/.server-scripts.conf
# edit ~/.server-scripts.conf and set DB_PASS and S3_BUCKET (and optionally DB_USER, BACKUP_DIR, LOG_DIR)
```
2. Important: ensure the file is owned by the user that runs cron and is mode `600`.

## Cron setup (what we use) ⏰
Paste these into `crontab -e` for user `ubuntu` (current setup):
```cron
# Trim Laravel logs (runs as blogger via sudo so it writes to /home/blogger/trim_laravel_logs.log)
45 3 * * * sudo -u blogger /home/ubuntu/server-scripts/trim_laravel_logs.sh >> /home/blogger/trim_laravel_logs.log 2>&1

# Weekly maintenance (delegates backups; guarded reboot)
0 3 * * 0 /home/ubuntu/server-scripts/weekly.sh >> /home/ubuntu/logs/cron.log 2>&1

# Weekly DB backups (gzip -> s3://$S3_BUCKET/weekly)
15 3 * * 0 /home/ubuntu/server-scripts/weekly_backup.sh >> /home/ubuntu/logs/weekly_backup.log 2>&1

# Daily gamenight backup at 02:00
0 2 * * * /home/ubuntu/server-scripts/daily_gamenight.sh >> /home/ubuntu/logs/daily_gamenight.log 2>&1
```

## How to test manually 🧪
- Run daily backup and inspect log:
```bash
/home/ubuntu/server-scripts/daily_gamenight.sh
tail -n 200 /home/ubuntu/logs/daily_gamenight.log
aws s3 ls s3://$S3_BUCKET/daily/ | tail -n 10
```
- Run weekly backup and inspect log:
```bash
/home/ubuntu/server-scripts/weekly_backup.sh
tail -n 200 /home/ubuntu/logs/weekly_backup.log
aws s3 ls s3://$S3_BUCKET/weekly/ | tail -n 10
```
- Run maintenance (dry-run; will not reboot):
```bash
/home/ubuntu/server-scripts/weekly.sh
tail -n 200 /home/ubuntu/logs/weekly_maintenance.log
```
- Run trim job as blogger (confirm log writes):
```bash
sudo -u blogger /home/ubuntu/server-scripts/trim_laravel_logs.sh
tail -n 200 /home/blogger/trim_laravel_logs.log
```

## Recommended maintenance & security checklist (minimal) ✅
- Store **no secrets** in the repo; use `~/.server-scripts.conf` (mode 600). 🔒
- Use a **non-root MySQL backup user** with minimal privileges for dumps (SELECT, LOCK TABLES, SHOW VIEW, TRIGGER). 👤
- Ensure `aws` CLI credentials or instance profile with S3 PutObject access for the cron-running user. 🔑
- Consider S3 lifecycle rules to expire or archive old backups (daily → 7d, weekly → 12w). ♻️
- Keep scripts executable and owned by `ubuntu` (or appropriate user) and logs writable by the target user: `chmod 700` for scripts and `chmod 700` for `/home/ubuntu/logs`. 🔧
- Avoid rebooting automatically from within a maintenance script; require an explicit flag or sentinel file to reboot. ♻️
- Add monitoring/alerts for failed backups (e.g., CloudWatch, simple cron-email, or a small healthcheck). 🚨

## Notifications (Pushover)
We provide a small wrapper `pushover_notify.sh` to send alerts via Pushover. Configure your Pushover app token and user key in `~/.server-scripts.conf`:

```bash
PUSHOVER_API_TOKEN="<your_app_token>"
PUSHOVER_USER_KEY="<your_user_key>"
```

Basic usage example:
```bash
# send a critical message
/home/ubuntu/server-scripts/pushover_notify.sh -t "Backup failed" -m "mysqldump failed for gamenight" --priority 1
```

Add notification calls from other scripts (example on backup error):
```bash
/home/ubuntu/server-scripts/pushover_notify.sh -t "Backup failed" -m "weekly_backup failed for gamenight" --priority 1
```

## Deploying to production
- This repo is intentionally minimal for deploy: copy scripts to `/home/ubuntu/server-scripts`, ensure the config exists at `/home/ubuntu/.server-scripts.conf` with mode `600`, and add cron entries to `ubuntu`'s crontab (see above). 🛠️

## Contact & changes
- If you want I can add a `README` section documenting who to notify on failures and a simple `healthcheck.sh` that verifies latest S3 backup timestamps. Tell me and I’ll add it as a separate pull request/commit.
