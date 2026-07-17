#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path
import getpass
import os
import subprocess
import shutil

import lib.Constants

def ask_sudopwd():
    sudo_password = input("Enter your sudo password: ")
    return sudo_password

def log_message(message, log_file=None):
    if log_file is None:
        script_name = Path(__file__).stem
        log_file = lib.Constants.log_path / f"system_log_{script_name}_{datetime.now().strftime('%Y%m%d')}.log"
    try:
        Path(lib.Constants.log_path).mkdir(parents=True, exist_ok=True)
        with open(log_file, 'a') as f:
            f.write(message + '\n')
    except Exception as e:
        print(f"Info =>: Failed to log message: {e}")

def clean_orphaned_logs(retention_days):
    log_dir = Path(lib.Constants.log_path)
    current_time = datetime.now()

    if not log_dir.exists():
        return

    for file_path in log_dir.glob("system_log_*.log"):
        file_time_str = file_path.stem.rsplit("_", 1)[-1]
        try:
            file_time = datetime.strptime(file_time_str, "%Y%m%d")
            if (current_time - file_time).days > retention_days:
                file_path.unlink()
                log_message(f"Info =>: Deleted orphaned log file: {file_path}")
        except ValueError:
            log_message(f"Info =>: Failed to parse date from log file name: {file_path.name}")

def get_current_user():
    return getpass.getuser()

def add_user(username):
    try:
        subprocess.run(['id', username], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        log_message(f"Info =>: User '{username}' already exists.")
    except subprocess.CalledProcessError:
        try:
            subprocess.run(['useradd', '-m', username], check=True)
            log_message(f"Info =>: User '{username}' has been added successfully.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to add user '{username}': {e}")

def remove_user(username):
    try:
        subprocess.run(['id', username], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            subprocess.run(['userdel', username], check=True)
            log_message(f"Info =>: User '{username}' has been removed successfully.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to remove user '{username}': {e}")
    except subprocess.CalledProcessError:
        log_message(f"Info =>: User '{username}' does not exist.")

def grant_sudo_privileges(username):
    try:
        subprocess.run(['id', username], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            subprocess.run(['usermod', '-aG', 'sudo', username], check=True)
            log_message(f"Info =>: Sudo privileges granted to user '{username}'.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to grant sudo privileges to user '{username}': {e}")
    except subprocess.CalledProcessError:
        log_message(f"Info =>: User '{username}' does not exist.")

def add_to_group(username, groupname):
    try:
        subprocess.run(['id', username], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            subprocess.run(['usermod', '-aG', groupname, username], check=True)
            log_message(f"Info =>: User '{username}' has been added to group '{groupname}'.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to add user '{username}' to group '{groupname}': {e}")
    except subprocess.CalledProcessError:
        log_message(f"Info =>: User '{username}' does not exist.")

def list_packages_to_update():
    try:
        result = subprocess.run(['apt', 'list', '--upgradable'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        packages = result.stdout.decode('utf-8').splitlines()
        return packages[1:]
    except subprocess.CalledProcessError as e:
        log_message(f"Info =>: Failed to list upgradable packages: {e}")
        return []

def update_os():
    try:
        subprocess.run(['apt-get', 'update'], check=True)
        subprocess.run(['apt-get', 'upgrade', '-y'], check=True)
        log_message(f"Info =>: Operating system packages have been updated successfully.")
    except subprocess.CalledProcessError as e:
        log_message(f"Info =>: Failed to update operating system packages: {e}")

def setup_cronjobs():
    list_of_cronjobs = lib.Constants.list_of_cronjobs_to_apply
    for cronjob in list_of_cronjobs:
        try:
            current_crontab = subprocess.run(['crontab', '-l'], check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            existing_crontab = current_crontab.stdout if current_crontab.returncode == 0 else ""

            if cronjob in existing_crontab:
                log_message(f"Info =>: Cronjob '{cronjob}' is already present.")
                continue

            updated_crontab = existing_crontab.rstrip()
            if updated_crontab:
                updated_crontab += "\n"
            updated_crontab += cronjob + "\n"
            subprocess.run(['crontab', '-'], input=updated_crontab, text=True, check=True)
            log_message(f"Info =>: Cronjob '{cronjob}' has been set up successfully.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to set up cronjob '{cronjob}': {e}")

def check_github_profile():
    try:
        result_name = subprocess.run(['git', 'config', '--global', 'user.name'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        result_email = subprocess.run(['git', 'config', '--global', 'user.email'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        username = result_name.stdout.decode('utf-8').strip()
        email = result_email.stdout.decode('utf-8').strip()
        if username and email:
            log_message(f"Info =>: GitHub profile is set up with username: {username}, email: {email}")
            return True
        else:
            log_message(f"Info =>: GitHub profile is not set up.")
            current_user = os.environ.get('SUDO_USER') or getpass.getuser()
            subprocess.run(['git', 'config', '--global', 'user.name', current_user], check=True)
            subprocess.run(['git', 'config', '--global', 'user.email', f'{current_user}@{lib.Constants.domain}'], check=True)
            return False
    except subprocess.CalledProcessError as e:
        log_message(f"Info =>: Failed to check GitHub profile: {e}")
        return False

def sync_git_repo():
    git_local_path = lib.Constants.git_local_path
    git_repo_url = lib.Constants.git_repo_url

    if not os.path.exists(git_local_path):
        try:
            subprocess.run(['git', 'clone', git_repo_url, git_local_path], check=True)
            log_message(f"Info =>: Git repository cloned to '{git_local_path}'.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to clone Git repository: {e}")
    else:
        try:
            subprocess.run(['git', '-C', git_local_path, 'pull'], check=True)
            log_message(f"Info =>: Git repository at '{git_local_path}' has been updated.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to update Git repository: {e}")

def rsync_git_repo():
    git_local_path = lib.Constants.git_local_path
    git_node_mount_path = lib.Constants.git_node_mount_path
    git_repo_url = lib.Constants.git_repo_url

    if not os.path.exists(git_node_mount_path):
        try:
            subprocess.run(['git', 'clone', git_repo_url, git_node_mount_path], check=True)
            log_message(f"Info =>: Git repository cloned to '{git_node_mount_path}'.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to clone Git repository: {e}")
    else:
        try:
            subprocess.run(['rsync', '-av', '--delete', f'{git_local_path}/', f'{git_node_mount_path}/'], check=True)
            log_message(f"Info =>: Git repository at '{git_node_mount_path}' has been synchronized.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to synchronize Git repository: {e}")

def get_cpu_usage():
    try:
        result = subprocess.run(['top', '-bn1'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode('utf-8')
        for line in output.splitlines():
            if "cpu" in line.lower():
                parts = line.replace(',', '.').split()
                for i, part in enumerate(parts):
                    if "id" in part and i > 0:
                        idle = float(parts[i-1].strip('%'))
                        return round(100.0 - idle, 1)
        return 0.0
    except Exception as e:
        log_message(f"Info =>: Failed to get CPU usage: {e}")
        return 0.0

def get_memory_usage():
    try:
        result = subprocess.run(['free', '-m'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode('utf-8')
        lines = output.splitlines()
        if len(lines) > 1:
            mem_line = lines[1]
            parts = mem_line.split()
            total_mem = float(parts[1])
            used_mem = float(parts[2])
            if total_mem > 0:
                return round((used_mem / total_mem) * 100, 1)
        return 0.0
    except Exception as e:
        log_message(f"Info =>: Failed to get memory usage: {e}")
        return 0.0

def get_disk_usage():
    try:
        total, used, free = shutil.disk_usage("/")
        if total > 0:
            return round((used / total) * 100, 1)
        return 0.0
    except Exception as e:
        log_message(f"Info =>: Failed to get disk usage: {e}")
        return 0.0

def get_inode_usage():
    try:
        result = subprocess.run(['df', '-i', '/'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode('utf-8')
        lines = output.splitlines()
        if len(lines) > 1:
            inode_line = lines[1]
            parts = inode_line.split()
            total_inodes = float(parts[1])
            used_inodes = float(parts[2])
            if total_inodes > 0:
                return round((used_inodes / total_inodes) * 100, 1)
        return 0.0
    except Exception as e:
        log_message(f"Info =>: Failed to get inode usage: {e}")
        return 0.0

def get_io_usage():
    try:
        result = subprocess.run(['iostat', '-dx'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode('utf-8')
        for line in reversed(output.splitlines()):
            parts = line.split()
            if not parts:
                continue
            try:
                io_usage = float(parts[-1].replace(',', '.'))
                return io_usage
            except ValueError:
                continue
        return 0.0
    except Exception as e:
        log_message(f"Info =>: Failed to get IO usage: {e}")
        return 0.0
