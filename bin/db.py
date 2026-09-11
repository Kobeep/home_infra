#!/usr/bin/env python3
"""
Sync pod and ingress state from the homelab API into a local SQLite database.
"""
import json
import os
import sqlite3
import urllib.request
from collections.abc import Mapping
from pathlib import Path


DB_PATH = os.environ.get("SERVICES_DB_PATH", "/var/services/db.sqlite")
API_BASE_URL = os.environ.get("HOMELAB_API_URL", "http://localhost:8000").rstrip("/")


def fetch_json(url: str) -> Mapping[str, object]:
    with urllib.request.urlopen(url, timeout=10) as response:
        payload = json.load(response)
    if not isinstance(payload, dict):
        raise ValueError(f"Expected an object from {url}")
    return payload


def validate_pods(payload: Mapping[str, object]) -> list[tuple[str, str, str]]:
    pods = payload.get("pods")
    if not isinstance(pods, list):
        raise ValueError("The pods API response must contain a list named 'pods'")

    validated = []
    for index, pod in enumerate(pods):
        if not isinstance(pod, dict):
            raise ValueError(f"Pod at index {index} must be an object")
        values = tuple(pod.get(field) for field in ("name", "namespace", "status"))
        if not all(isinstance(value, str) and value for value in values):
            raise ValueError(f"Pod at index {index} is missing name, namespace, or status")
        validated.append(values)
    return validated


def validate_ingresses(payload: Mapping[str, object]) -> list[tuple[str, str, str]]:
    ingresses = payload.get("ingresses")
    if not isinstance(ingresses, list):
        raise ValueError("The ingresses API response must contain a list named 'ingresses'")

    validated = []
    for index, ingress in enumerate(ingresses):
        if not isinstance(ingress, dict):
            raise ValueError(f"Ingress at index {index} must be an object")
        name = ingress.get("name")
        namespace = ingress.get("namespace")
        hosts = ingress.get("hosts", [])
        if not isinstance(name, str) or not name or not isinstance(namespace, str) or not namespace:
            raise ValueError(f"Ingress at index {index} is missing name or namespace")
        if not isinstance(hosts, list) or not all(isinstance(host, str) for host in hosts):
            raise ValueError(f"Ingress at index {index} must contain a list of string hosts")
        validated.append((name, namespace, ", ".join(hosts) if hosts else "N/A"))
    return validated


def refresh_database(
    db_path: str,
    pods: list[tuple[str, str, str]],
    ingresses: list[tuple[str, str, str]],
) -> None:
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db_path) as connection:
        connection.execute(
            """CREATE TABLE IF NOT EXISTS pods (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                namespace TEXT NOT NULL,
                status TEXT NOT NULL
            )"""
        )
        connection.execute(
            """CREATE TABLE IF NOT EXISTS ingresses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                namespace TEXT NOT NULL,
                host TEXT NOT NULL
            )"""
        )
        connection.execute("DELETE FROM pods")
        connection.execute("DELETE FROM ingresses")
        connection.executemany(
            "INSERT INTO pods (name, namespace, status) VALUES (?, ?, ?)",
            pods,
        )
        connection.executemany(
            "INSERT INTO ingresses (name, namespace, host) VALUES (?, ?, ?)",
            ingresses,
        )


def main() -> None:
    try:
        pods_data = fetch_json(f"{API_BASE_URL}/api/kubernetes/pods")
        ingress_data = fetch_json(f"{API_BASE_URL}/api/kubernetes/ingresses")
        pods = validate_pods(pods_data)
        ingresses = validate_ingresses(ingress_data)
        refresh_database(DB_PATH, pods, ingresses)
    except (OSError, sqlite3.Error, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"ERROR: Failed to update database from {API_BASE_URL}: {error}") from error

    print(f"Info =>: Database successfully updated from {API_BASE_URL}")


if __name__ == "__main__":
    main()
