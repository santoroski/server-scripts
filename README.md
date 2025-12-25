# server-scripts

Maintenance scripts for the server: weekly maintenance and daily `gamenight` backup to S3.

## Quick start
1. Copy the example config and edit it with your secrets:
   ```bash
   cp .server-scripts.conf.example ~/.server-scripts.conf
   chmod 600 ~/.server-scripts.conf
   # then edit ~/.server-scripts.conf and set DB_PASS, S3_BUCKET_DAILY, etc.
   ```
2. Test the daily backup manually:
   ```bash
   ./daily_gamenight.sh
   tail -n 200 /home/ubuntu/logs/daily_gamenight.log
   ```
3. Install cron job to run daily at 02:00:
   ```bash
   (crontab -l 2>/dev/null; echo "0 2 * * * /home/pi/server-scripts/daily_gamenight.sh >> /home/ubuntu/logs/daily_gamenight.log 2>&1") | crontab -
   ```

## Security notes
- **Never** commit your real `.server-scripts.conf` (it's in `.gitignore`). Keep credentials secret and use `chmod 600`.
- Ensure AWS CLI is configured for the user that runs the cron job.

## Want to push to GitHub?
If you want, I can create a remote repository and push this repository for you (requires `gh` or GitHub access).