#!/usr/bin/env python3

# Startup hook script to perform initial setup tasks
from pathlib import Path
import sys

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
	sys.path.insert(0, str(ROOT_DIR))

import lib.Utils

lib.Utils.setup_cronjobs()
