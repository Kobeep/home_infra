#!/usr/bin/env python3
from pathlib import Path
import argparse
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
    parser.add_argument("--action", help="Enter action to perform (add, remove, grant_sudo)", required=True)
    parser.add_argument("--password", help="Enter password for the user (only required for adding a user)", required=False)
    parser.add_argument("--groupname", help="Enter group name to add the user to (only required for adding to a group)", required=False)
    args = parser.parse_args()

    if not args.username:
        print("INFO ==> Didnt provide any user. Setting default username to 'ubuntuserver'.")
        args.username = lib.Constants.proposed_username
    elif not args.password and args.action == "add":
        print("INFO ==> Didnt provide any password. Setting default password to 'ubuntuserver'.")
        args.password = lib.Constants.proposed_username
    elif not args.groupname and args.action == "add_to_group":
        print("INFO ==> Didnt provide any group name. Setting default group name to 'service'.")
        args.groupname = lib.Constants.proposed_groupname
    elif not args.action:
        print("INFO ==> Didnt provide any action.")
        exit(1)

    if args.action == "add":
        lib.Utils.add_user(args.username)
        if args.password:
            run_privileged_command(['chpasswd'], input=f"{args.username}:{args.password}", text=True, check=True)
    elif args.action == "remove":
        lib.Utils.remove_user(args.username)
    elif args.action == "grant_sudo":
        lib.Utils.grant_sudo_privileges(args.username)
    elif args.action == "add_to_group":
        lib.Utils.add_to_group(args.username, args.groupname)
    else:
        print("INFO ==> Invalid action specified.")
        exit(1)

if __name__ == "__main__":
    main()
