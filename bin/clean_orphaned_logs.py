#!/usr/bin/env python3
import lib.Utils;
import lib.Constants;

lib.Utils.clean_orphaned_logs(lib.Constants.retention_days)
