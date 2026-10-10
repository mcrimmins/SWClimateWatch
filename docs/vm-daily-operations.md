# VM daily operations

The VM uses a tested code version in `/home/crimmins/RProjects/SWClimateWatch`.
The laptop remains the development environment. Start with staging, confirm
one unattended run, then make the VM the only routine publisher to the live site.
No automatic Git pulls or two-way data synchronization are involved.

## Install the runner configuration

After committing these files on the laptop and transferring the tested code
to the VM, run these commands as `crimmins` on the VM:

```bash
cd /home/crimmins/RProjects/SWClimateWatch
mkdir -p /home/crimmins/.config/swclimatewatch
cp -n scripts/production.env.example /home/crimmins/.config/swclimatewatch/production.env
chmod 600 /home/crimmins/.config/swclimatewatch/production.env
command -v Rscript quarto aws flock crontab
nano /home/crimmins/.config/swclimatewatch/production.env
```

Keep `watch-staging/` as the destination. Adjust PATH to include the directories
reported for Rscript, Quarto and AWS CLI. Uncomment the ntfy topic setting if
you want the existing phone alerts. Configuration and any tokens stay outside
Git. The runner sets Arizona time and us-west-2 explicitly.

Check the installed environment without updating data or uploading:

```bash
bash scripts/run-production-daily.sh --check
```

Then test a complete run manually:

```bash
bash scripts/run-production-daily.sh
```

This updates data and publishes to the configured destination. It retains the
existing render/validation gates and non-deleting S3 sync. Use this runner for
manual VM runs too; running the R entry point directly bypasses its overlap lock.
The lock covers the whole workflow, including render and sync. An overlapping
invocation prints `SKIPPED` and exits successfully; it does not start a second job.
The operating system releases the lock when the processes finish. Do not delete
`daily.lock`, including during recovery.

Each run saves console output under
`/home/crimmins/.local/state/swclimatewatch/logs/`. It records the Git commit,
destination, start time, exit status and total seconds. The R workflow still
provides detailed diagnostics and ntfy progress, success and error notices.
Failures before R starts appear in the scheduler log; a machine shutdown cannot
send a final phone notice. Logs are retained until you archive or remove them.

## Schedule staging at 8 a.m. Arizona time

Confirm the VM uses Cronie and its service is active:

```bash
rpm -q cronie
systemctl is-active crond
```

If it is missing or inactive, have the VM administrator install/enable Cronie
before scheduling. Edit your own crontab with `crontab -e`; preserve any existing
jobs. Add the following lines (the command must be one line):

```cron
SHELL=/bin/bash
CRON_TZ=America/Phoenix
0 8 * * * /bin/bash /home/crimmins/RProjects/SWClimateWatch/scripts/run-production-daily.sh >> /home/crimmins/.local/state/swclimatewatch/scheduler.log 2>&1
```

`CRON_TZ` controls the schedule; the runner's `TZ` controls R's calendar date.
Cronie documents this distinction in its
[crontab manual](https://github.com/cronie-crond/cronie/blob/master/man/crontab.5).
The check/manual run above creates the state directory before cron uses it.
`CRON_TZ` also affects other following jobs in the same table, so restore their
original scheduling timezone if needed. Verify the saved entry with `crontab -l`.

After the next scheduled run:

```bash
tail -n 20 /home/crimmins/.local/state/swclimatewatch/scheduler.log
ls -lt /home/crimmins/.local/state/swclimatewatch/logs/ | head
```

Confirm the final destination is staging, validation passed, dates advanced as
available, and phone reporting worked. Cron does not retry failed runs that day
or catch up a run missed while the VM was off. A manual invocation of the same
runner is the recovery command; existing data caches and pending-work handling
apply. Keep the laptop as live publisher during this staging trial.

## Controlled code releases

Use an explicitly tested commit, not an automatic pull of the newest main.
First commit/push changes on the laptop. On the VM, take the same lock in a
dedicated terminal. If it is busy, wait for the update to finish and try again:

```bash
cd /home/crimmins/RProjects/SWClimateWatch
mkdir -p /home/crimmins/.local/state/swclimatewatch
exec 9>/home/crimmins/.local/state/swclimatewatch/daily.lock
flock -n 9
```

**Continue only if `flock` succeeded.** Inspect changes before changing code:

```bash
git status --short
git diff -- site/index.qmd site/pages/current-snow.qmd
git rev-parse HEAD
```

Record the current commit for rollback. If the only changes are the generated
dates in those two pages, preserve them in a named Git stash:

```bash
git stash push -m "VM generated page dates before release" -- site/index.qmd site/pages/current-snow.qmd
git status --short
```

If there are other changes, preserve and resolve them before proceeding; do not
reset or overwrite them. When the working tree is clean, fetch and select the
tested full commit hash supplied from the laptop:

```bash
git fetch origin
git checkout --detach TESTED_COMMIT_HASH
git rev-parse HEAD
```

Replace `TESTED_COMMIT_HASH` with the actual tested hash. This keeps the data,
maps and diagnostics in the existing checkout and pins code to a specific
release. The saved page dates remain recoverable with `git stash list` and
`git stash show -p`; do not automatically apply them to new code. The publisher
regenerates the pages using VM data. A code rollback uses the same procedure
with the recorded previous hash; it does not roll back data or cache formats.

Release the lock before checking or running the runner:

```bash
flock -u 9
exec 9>&-
bash scripts/run-production-daily.sh --check
```

Closing that dedicated terminal also releases its lock. Test new code against
staging before a live run. If the installed configuration normally targets live,
temporarily set its destination to staging for the release test and restore it
after the test passes.

## Live cutover

After a successful unattended staging run, pause routine laptop publication.
Ensure no VM job is running, then edit the private configuration to set:

```bash
SWC_S3_DESTINATION=s3://cales-climate-reports/climate/watch/
```

Run the runner manually, confirm the final destination and inspect the live
site. The existing schedule now uses live on its next run; no second cron job is
needed. Staging and live have separate publication success markers. Continue
development on the laptop and promote tested commits explicitly. For emergency
laptop publishing, pause the VM cron entry first to keep one live writer.
