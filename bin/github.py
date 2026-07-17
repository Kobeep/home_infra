#!/usr/bin/env python3
from pathlib import Path
import sys

project_root = Path(__file__).resolve().parent.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

import lib.Utils

def main():
    lib.Utils.check_github_profile()
    lib.Utils.sync_git_repo()

if __name__ == "__main__":
    main()
