#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
	sys.path.insert(0, str(ROOT_DIR))

import lib.Utils
import lib.Constants

lib.Utils.clean_orphaned_logs(lib.Constants.retention_days)
