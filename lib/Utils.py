#!/usr/bin/env python3
from datetime import datetime
import subprocess
import os
import paramiko
from datetime import datetime

def ask_sudopwd():
    sudo_password = input("Enter your sudo password: ")
    return sudo_password

# Logging function to log messages to a file
def log_message(message, log_file=None):
    if log_file is None:
        log_file = f"/var/services/{os.path.basename(__file__)}_{datetime.now().strftime('%Y%m%d')}.log"
    try:
        with open(log_file, 'a') as f:
            f.write(message + '\n')
    except Exception as e:
        print(f"Info =>: Failed to log message: {e}")

def clean_orphaned_logs(retention_days):
    log_dir = "/var/services/"
    current_time = datetime.now()

    for filename in os.listdir(log_dir):
        if filename.startswith("system_log_") and filename.endswith(".log"):
            file_path = os.path.join(log_dir, filename)
            file_time_str = filename[len("system_log_"):-len(".log")]
            try:
                file_time = datetime.strptime(file_time_str, "%Y%m%d")
                if (current_time - file_time).days > retention_days:
                    os.remove(file_path)
                    log_message(f"Info =>: Deleted orphaned log file: {file_path}")
            except ValueError:
                log_message(f"Info =>: Failed to parse date from log file name: {filename}")

# Manage identities and user accounts on the system
def add_user(username):
    try:
        # Check if the user already exists
        subprocess.run(['id', username], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        log_message(f"Info =>: User '{username}' already exists.")
    except subprocess.CalledProcessError:
        # User does not exist, proceed to add
        try:
            subprocess.run(['sudo', 'useradd', '-m', username], check=True)
            log_message(f"Info =>: User '{username}' has been added successfully.")
        except subprocess.CalledProcessError as e:
            log_message(f"Info =>: Failed to add user '{username}': {e}")

def remove_user(username):
    try:
        # Check if the user exists
        subprocess.run(['id', username], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # User exists, proceed to remove
        try:
            subprocess.run(['sudo', 'userdel', username], check=True)
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
            subprocess.run(['sudo', 'usermod', '-aG', 'sudo', username], check=True)
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
            subprocess.run(['sudo', 'usermod', '-aG', groupname, username], check=True)
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
        subprocess.run(['sudo', 'apt-get', 'update'], check=True)
        subprocess.run(['sudo', 'apt-get', 'upgrade', '-y'], check=True)
        log_message(f"Info =>: Operating system packages have been updated successfully.")
    except subprocess.CalledProcessError as e:
        log_message(f"Info =>: Failed to update operating system packages: {e}")
