#!/usr/bin/env python3

from pathlib import Path

# Constants
proposed_username = "service"
proposed_groupname = "service"
retention_days = 30
domain = "kobecloud.pl"
project_root = Path(__file__).resolve().parents[1]
git_local_path = str(project_root)
bin_path = project_root / "bin"
lib_path = project_root / "lib"
log_path = Path("/var/services/logs")
git_repo_url = "https://github.com/Kobeep/home_infra.git"



# Cronjob schedules
update_os_cronjob_schedule = "0 2 * * *"
update_os_cronjob_command = f"{update_os_cronjob_schedule} /usr/bin/python3 {bin_path / 'update_os.py'} >> {log_path}/system_log_update_os_$(date +\%Y\%m\%d).log 2>&1"

clean_orphaned_logs_cronjob_schedule = "0 3 * * *"
clean_orphaned_logs_cronjob_command = f"{clean_orphaned_logs_cronjob_schedule} /usr/bin/python3 {bin_path / 'clean_orphaned_logs.py'} >> {log_path}/system_log_clean_orphaned_logs_$(date +\%Y\%m\%d).log 2>&1"

github_cronjob_schedule = "0 4 * * *"
github_cronjob_command = f"{github_cronjob_schedule} /usr/bin/python3 {bin_path / 'github.py'} >> {log_path}/system_log_github_$(date +\%Y\%m\%d).log 2>&1"

###################################################################################################################
list_of_cronjobs_to_apply = [update_os_cronjob_command, clean_orphaned_logs_cronjob_command, github_cronjob_command]
###################################################################################################################
