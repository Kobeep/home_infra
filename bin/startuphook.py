#!/usr/bin/env python3

# Startup hook script to perform initial setup tasks
from pathlib import Path
import sys
import lib.Utils
import bin.monitor

lib.Utils.setup_cronjobs()

bin.monitor.main()
