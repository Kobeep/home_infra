#!/usr/bin/env python3

# Startup hook script to perform initial setup tasks
from pathlib import Path
import sys
import lib.Utils
import bin.monitor

project_root = Path(__file__).resolve().parent.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

lib.Utils.setup_cronjobs()

bin.monitor.main()
