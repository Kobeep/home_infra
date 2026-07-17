#!/usr/bin/env python3
from datetime import datetime
from pathlib import Path
import getpass
import os
import subprocess

import lib.Constants

def ask_sudopwd():
    sudo_password = input("Enter your sudo password: ")
    return sudo_password

# Logging function to log messages to a file
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

# Manage identities and user accounts on the system
def get_current_user():
    return getpass.getuser()

def add_user(username):
    try:
        # Check if the user already exists
        subprocess.run(['id', username], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        log_message(f"Info =>: User '{username}' already exists.")
    except subprocess.CalledProcessError:
        # User does not exist, proceed to add
        try:
            subprocess.run(['useradd', '-m', username], check=True)
            log_message(f"Info =>: User '{username}' has been added successfully.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to add user '{username}': {e}")

def remove_user(username):
    try:
        # Check if the user exists
        subprocess.run(['id', username], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # User exists, proceed to remove
        try:
            subprocess.run(['userdel', username], check=True)
            log_message(f"Info =>: User '{username}' has been removed successfully.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to remove user '{username}': {e}")
    except subprocess.CalledProcessError:
        log_message(f"Info =>: User '{username}' does not exist.")

def grant_sudo_privileges(username):
    try:
        # Check if the user exists
        subprocess.run(['id', username], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # User exists, proceed to grant sudo privileges
        try:
            subprocess.run(['usermod', '-aG', 'sudo', username], check=True)
            log_message(f"Info =>: Sudo privileges granted to user '{username}'.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to grant sudo privileges to user '{username}': {e}")
    except subprocess.CalledProcessError:
        log_message(f"Info =>: User '{username}' does not exist.")

def add_to_group(username, groupname):
    try:
        # Check if the user exists
        subprocess.run(['id', username], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # User exists, proceed to add to group
        try:
            subprocess.run(['usermod', '-aG', groupname, username], check=True)
            log_message(f"Info =>: User '{username}' has been added to group '{groupname}'.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to add user '{username}' to group '{groupname}': {e}")
    except subprocess.CalledProcessError:
        log_message(f"Info =>: User '{username}' does not exist.")

# Update the operating system packages
def list_packages_to_update():
    try:
        result = subprocess.run(['apt', 'list', '--upgradable'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        packages = result.stdout.decode('utf-8').splitlines()
        return packages[1:]  # Skip the first line which is a header
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


# Setup cronjobs for updating the OS and cleaning orphaned logs
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

# github.py functions
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
# rsync git repo from local to node path
def rsync_git_repo():
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

# Monitoring functions
def get_cpu_usage():
    try:
        result = subprocess.run(['top', '-bn1'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode('utf-8')
        for line in output.splitlines():
            if "Cpu(s)" in line or "cpu" in line.lower():
                # Bezpieczne wyciąganie wartości: szukamy wolnego procesora (id / idle)
                # i odejmujemy od 100, co jest najbardziej uniwersalne.
                parts = line.split()
                for i, part in enumerate(parts):
                    if "id" in part:  # szukamy np. "95.2 id,"
                        # bierzemy element tuż przed "id"
                        idle = float(parts[i-1].replace(',', '.'))
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
        mem_line = lines[1]
        total_mem = float(mem_line.split()[1])
        used_mem = float(mem_line.split()[2])
        memory_usage = (used_mem / total_mem) * 100
        return memory_usage
    except subprocess.CalledProcessError as e:
        log_message(f"Info =>: Failed to get memory usage: {e}")
        return 0.0

def get_disk_usage():
    try:
        result = subprocess.run(['df', '-h'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode('utf-8')
        lines = output.splitlines()
        disk_line = lines[1]
        total_disk = float(disk_line.split()[1].replace('G', ''))
        used_disk = float(disk_line.split()[2].replace('G', ''))
        disk_usage = (used_disk / total_disk) * 100
        return disk_usage
    except subprocess.CalledProcessError as e:
        log_message(f"Info =>: Failed to get disk usage: {e}")
        return 0.0

def get_inode_usage():
    try:
        result = subprocess.run(['df', '-i'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode('utf-8')
        lines = output.splitlines()
        inode_line = lines[1]
        total_inodes = float(inode_line.split()[1])
        used_inodes = float(inode_line.split()[2])
        inode_usage = (used_inodes / total_inodes) * 100
        return inode_usage
    except subprocess.CalledProcessError as e:
        log_message(f"Info =>: Failed to get inode usage: {e}")
        return 0.0

def get_io_usage():
    try:
        result = subprocess.run(['iostat', '-dx'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output = result.stdout.decode('utf-8')
        lines = output.splitlines()
        io_line = lines[-1]
        io_usage = float(io_line.split()[-1])
        return io_usage
    except subprocess.CalledProcessError as e:
        log_message(f"Info =>: Failed to get IO usage: {e}")
        return 0.0
