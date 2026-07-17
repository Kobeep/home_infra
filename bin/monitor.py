#!/usr/bin/env python3
# Monitoring process to check if the system is running and healthy
from pathlib import Path
import lib.Utils
import time

def main():
  # Check CPU usage
  cpu_usage = lib.Utils.get_cpu_usage()

  # Check memory usage
  memory_usage = lib.Utils.get_memory_usage()

  # Check disk usage
  disk_usage = lib.Utils.get_disk_usage()

  # Check Inode usage
  inode_usage = lib.Utils.get_inode_usage()

  # Check IO usage
  io_usage = lib.Utils.get_io_usage()

  # Check if the system is running low on resources
  if cpu_usage > 80:
      lib.Utils.log_message(f"Warning =>: High CPU usage detected: {cpu_usage}%")

  if memory_usage > 80:
      lib.Utils.log_message(f"Warning =>: High memory usage detected: {memory_usage}%")

  if disk_usage > 80:
      lib.Utils.log_message(f"Warning =>: High disk usage detected: {disk_usage}%")

  if inode_usage > 80:
      lib.Utils.log_message(f"Warning =>: High inode usage detected: {inode_usage}%")

  if io_usage > 80:
      lib.Utils.log_message(f"Warning =>: High IO usage detected: {io_usage}%")

    # Keep the script running indefinitely to continuously monitor the system
  while True:
      time.sleep(60)

if __name__ == "__main__":
      main()
