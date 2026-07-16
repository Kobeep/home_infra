#!/usr/bin/env python3

# Constants
proposed_username = "service"
proposed_groupname = "service"
retention_days = 30

git_local_path = "/home/$USER/home_infra"
bin_path = "$git_local_path/bin"
lib_path = "$git_local_path/lib"
log_path = "/var/services/logs"
git_repo_url = "https://github.com/Kobeep/home_infra.git"



# Cronjob schedules
update_os_cronjob_schedule = "0 2 * * *"
update_os_cronjob_command = f"{update_os_cronjob_schedule} /usr/bin/python3 {bin_path}/update_os.py >> {log_path}/cron_update_os$(date +\%Y\%m\%d).log 2>&1"

clean_orphaned_logs_cronjob_schedule = "0 3 * * *"
clean_orphaned_logs_cronjob_command = f"{clean_orphaned_logs_cronjob_schedule} /usr/bin/python3 {bin_path}/clean_orphaned_logs.py >> {log_path}/cron_clean_orphaned_logs$(date +\%Y\%m\%d).log 2>&1"

github_cronjob_schedule = "0 4 * * *"
github_cronjob_command = f"{github_cronjob_schedule} /usr/bin/python3 {bin_path}/github.py >> {log_path}/cron_github$(date +\%Y\%m\%d).log 2>&1"

###################################################################################################################
list_of_cronjobs_to_apply = [update_os_cronjob_command, clean_orphaned_logs_cronjob_command, github_cronjob_command]
###################################################################################################################
