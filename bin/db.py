#!/usr/bin/env python3
import os
import urllib.request
import sqlite3
import json
import ssl

DB_PATH = "/var/services/db.sqlite"

if not os.path.isfile(DB_PATH):
    print("Info =>: Database not found. Creating a new database file...")
    try:
        os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
        with open(DB_PATH, 'w'): pass
    except Exception as e:
        print(f"Info =>: Failed to create database directory or file: {e}")
        exit(1)

pods_url = "https://api.192.168.1.24.nip.io/api/kubernetes/pods"
ingresses_url = "https://api.192.168.1.24.nip.io/api/kubernetes/ingresses"

ssl_context = ssl._create_unverified_context()

try:
    with urllib.request.urlopen(pods_url, context=ssl_context) as resp:
        pods_data = json.load(resp)

    with urllib.request.urlopen(ingresses_url, context=ssl_context) as resp:
        ingress_data = json.load(resp)
except Exception as e:
    print(f"Info =>: Error fetching data from API: {e}")
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

print("Info =>: Database successfully updated with pods and ingresses!")
