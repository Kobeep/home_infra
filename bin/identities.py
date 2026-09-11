#!/usr/bin/env python3
from pathlib import Path
import argparse
import getpass
import subprocess
import sys

project_root = Path(__file__).resolve().parent.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

import lib.Utils
import lib.Constants
from lib.Utils import run_privileged_command

def main():
    parser = argparse.ArgumentParser(description="Manage system users")
    parser.add_argument("--username", help="Enter username to add or remove", required=True)
    parser.add_argument(
        "--action",
        choices=["add", "remove", "grant_sudo", "add_to_group"],
        help="Enter action to perform",
        required=True,
    )
    parser.add_argument("--groupname", help="Enter group name to add the user to (only required for adding to a group)", required=False)
    args = parser.parse_args()

    if args.action == "add":
        password = getpass.getpass("Enter password for the new user: ")
        password_confirmation = getpass.getpass("Confirm password: ")
        if password != password_confirmation:
            parser.error("Passwords do not match")
        if not lib.Utils.add_user(args.username):
            raise SystemExit(1)
        try:
            run_privileged_command(
                ["chpasswd"],
                input=f"{args.username}:{password}",
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as error:
            raise SystemExit(f"ERROR: Failed to set password: {error}") from error
    elif args.action == "remove":
        if not lib.Utils.remove_user(args.username):
            raise SystemExit(1)
    elif args.action == "grant_sudo":
        if not lib.Utils.grant_sudo_privileges(args.username):
            raise SystemExit(1)
    elif args.action == "add_to_group":
        groupname = args.groupname or lib.Constants.proposed_groupname
        if not lib.Utils.add_to_group(args.username, groupname):
            raise SystemExit(1)

if __name__ == "__main__":
    main()
