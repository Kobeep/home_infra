#!/usr/bin/env python3
"""
db.py - Syncs pod and ingress state from the homelab API into a local SQLite DB.

The API base URL is read from the HOMELAB_API_URL environment variable.
This defaults to http://localhost:8000 so the script can be run directly
on the server by the 'server' user without any external dependency on a
specific IP or SSL certificate.
"""
import os
import urllib.request
import sqlite3
import json

DB_PATH = "/var/services/db.sqlite"
API_BASE_URL = os.environ.get("HOMELAB_API_URL", "http://localhost:8000")

pods_url = f"{API_BASE_URL}/api/kubernetes/pods"
ingresses_url = f"{API_BASE_URL}/api/kubernetes/ingresses"

if not os.path.isfile(DB_PATH):
    print("Info =>: Database not found. Creating a new database file...")
    try:
        os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
        with open(DB_PATH, 'w'):
            pass
    except Exception as e:
        print(f"Info =>: Failed to create database directory or file: {e}")
        exit(1)

try:
    with urllib.request.urlopen(pods_url, timeout=10) as resp:
        pods_data = json.load(resp)

    with urllib.request.urlopen(ingresses_url, timeout=10) as resp:
        ingress_data = json.load(resp)
except Exception as e:
    print(f"Info =>: Error fetching data from API ({API_BASE_URL}): {e}")
    exit(1)

conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

cursor.execute('''CREATE TABLE IF NOT EXISTS pods (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    namespace TEXT NOT NULL,
                    status TEXT NOT NULL
                )''')

cursor.execute('''CREATE TABLE IF NOT EXISTS ingresses (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    namespace TEXT NOT NULL,
                    host TEXT NOT NULL
                )''')

cursor.execute("DELETE FROM pods")
cursor.execute("DELETE FROM ingresses")

for pod in pods_data.get('pods', []):
    name = pod.get('name')
    namespace = pod.get('namespace')
    status = pod.get('status')
    cursor.execute(
        "INSERT INTO pods (name, namespace, status) VALUES (?, ?, ?)",
        (name, namespace, status)
    )

for ingress in ingress_data.get('ingresses', []):
    name = ingress.get('name')
    namespace = ingress.get('namespace')
    hosts = ", ".join(ingress.get('hosts', [])) if ingress.get('hosts') else "N/A"
    cursor.execute(
        "INSERT INTO ingresses (name, namespace, host) VALUES (?, ?, ?)",
        (name, namespace, hosts)
    )

conn.commit()
conn.close()

print(f"Info =>: Database successfully updated from {API_BASE_URL}")
