#!/usr/bin/env python3
# Script destined to generate/update sqlite database with pods informations (hostname, ip, status, etc.) from homelab-api -> api/kubernetes.
import os
import urllib.request
import sqlite3

# download/setup sqlite database if not exists
if not os.path.isfile("/var/service/db.sqlite"):
    print("Database not found. Downloading...")
    urllib.request.urlretrieve("https://example.com/path/to/db.sqlite", "/var/service/db.sqlite")

# Gather pods informations from homelab-api -> api/kubernetes
request1 = urllib.request.Request("http://api.192.168.1.24.nip.io/api/kubernetes/pods")
request2 = urllib.request.Request("http://api.192.168.1.24.nip.io/api/kubernetes/ingresses")
# Api returns a JSON with all pods informations, we need to parse it and store it in the sqlite database.

with urllib.request.urlopen(request) as response:
    import json
    data = json.load(response)

# Connect to the sqlite database and update it with the pods informations
conn = sqlite3.connect("/var/service/db.sqlite")
cursor = conn.cursor()

# Create table if not exists
cursor.execute('''CREATE TABLE IF NOT EXISTS pods (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    namespace TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )''')

# Clear existing data
cursor.execute("DELETE FROM pods")

# Insert new data
for pod in data['items']:
    name = pod['metadata']['name']
    namespace = pod['metadata']['namespace']
    status = pod['status']['phase']

    cursor.execute("INSERT INTO pods (name, namespace, status, ip, node_name, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                   (name, namespace, status))

conn.commit()
conn.close()
