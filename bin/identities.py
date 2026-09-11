#!/usr/bin/env python3
from pathlib import Path
import argparse
import getpass
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
<<<<<<< HEAD
        if not lib.Utils.add_user(args.username):
            raise SystemExit(1)
        if args.password:
            try:
                run_privileged_command(['chpasswd'], input=f"{args.username}:{args.password}", text=True, check=True)
            except subprocess.CalledProcessError:
                raise SystemExit(1)
=======
        lib.Utils.add_user(args.username)
        password = getpass.getpass("Enter password for the new user: ")
        password_confirmation = getpass.getpass("Confirm password: ")
        if password != password_confirmation:
            parser.error("Passwords do not match")
        run_privileged_command(["chpasswd"], input=f"{args.username}:{password}", text=True, check=True)
>>>>>>> 02259b9 (Fix secure user password handling (#35) (#39))
    elif args.action == "remove":
        if not lib.Utils.remove_user(args.username):
            raise SystemExit(1)
    elif args.action == "grant_sudo":
        if not lib.Utils.grant_sudo_privileges(args.username):
            raise SystemExit(1)
    elif args.action == "add_to_group":
<<<<<<< HEAD
        if not lib.Utils.add_to_group(args.username, args.groupname):
            raise SystemExit(1)
    else:
        print("INFO ==> Invalid action specified.")
        exit(1)
=======
        groupname = args.groupname or lib.Constants.proposed_groupname
        lib.Utils.add_to_group(args.username, groupname)
>>>>>>> 02259b9 (Fix secure user password handling (#35) (#39))

if __name__ == "__main__":
    main()
