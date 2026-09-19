"""
dag_generator.py
----------------
Skanuje folder ./dags/configs/ w poszukiwaniu plików .conf (HOCON)
i automatycznie generuje z nich DAGi w Airflow (kompatybilne z Airflow 2 i 3).
"""

import os
from datetime import datetime
from pyhocon import ConfigFactory

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

# Ścieżka do folderu z plikami HOCON wewnątrz kontenera Airflow
CONFIGS_DIR = os.path.join(os.path.dirname(__file__), "configs")


def create_python_callable(msg: str):
    """Pomocnicza funkcja generująca zadania PythonOperator."""
    def _callable():
        print(f"\n==========================================")
        print(f"[FLINK SIMULATION]: {msg}")
        print(f"==========================================\n")
    return _callable


def generate_dag_from_hocon(config_path: str) -> DAG:
    """Parsuje plik HOCON i buduje obiekt DAG."""
    # 1. Odczyt konfiguracji HOCON
    conf = ConfigFactory.parse_file(config_path)
    pipeline_conf = conf.get("pipeline")

    dag_id = pipeline_conf.get("id")
    schedule = pipeline_conf.get("schedule", None)
    description = pipeline_conf.get("description", "")
    owner = pipeline_conf.get("owner", "airflow")

    default_args = {
        "owner": owner,
        "start_date": datetime(2024, 1, 1),
    }

    # 2. Tworzenie DAG-a
    dag = DAG(
        dag_id=dag_id,
        default_args=default_args,
        schedule=schedule,  # Składnia Airflow 3+
        catchup=False,
        description=description,
        tags=["hocon", "generated"],
    )

    previous_task = None

    with dag:
        for task_conf in pipeline_conf.get("tasks", []):
            task_id = task_conf.get("id")
            task_type = task_conf.get("type")

            if task_type == "bash":
                current_task = BashOperator(
                    task_id=task_id,
                    bash_command=task_conf.get("command"),
                )
            elif task_type == "python":
                current_task = PythonOperator(
                    task_id=task_id,
                    python_callable=create_python_callable(
                        task_conf.get("message", "Brak wiadomości")
                    ),
                )
            else:
                raise ValueError(f"Nieobsługiwany typ zadania: {task_type}")

            if previous_task:
                previous_task >> current_task
            previous_task = current_task

    return dag


# ------------------------------------------------------------------
# REJESTRACJA DAG-ÓW W AIRFLOW
# Airflow szuka w plikach zmiennych globalnych typu DAG
# ------------------------------------------------------------------
if os.path.exists(CONFIGS_DIR):
    for filename in os.listdir(CONFIGS_DIR):
        if filename.endswith(".conf"):
            full_path = os.path.join(CONFIGS_DIR, filename)
            try:
                new_dag = generate_dag_from_hocon(full_path)

                globals()[new_dag.dag_id] = new_dag
            except Exception as e:
                print(f"Błąd ładowania pliku HOCON {filename}: {e}")
