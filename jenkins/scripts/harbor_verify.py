import base64
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request


def load_harbor_env_file(file_path: str) -> dict:
    values = {}
    if not os.path.exists(file_path):
        return values
    with open(file_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            values[key.strip()] = val.strip()
    return values


def pick(key: str, fallback: dict) -> str:
    v = os.getenv(key, "").strip()
    if v:
        return v
    return fallback.get(key, "")


def main() -> None:
    fallback = load_harbor_env_file(".harbor_env")

    owner_user = os.getenv("HARBOR_OWNER_USER", "")
    owner_pass = os.getenv("HARBOR_OWNER_PASS", "")
    host_value = pick("REGISTRY_HOST", fallback)
    project_name = pick("PROJECT_NAME", fallback)
    repository_name = pick("REPOSITORY_NAME", fallback)
    image_tag = pick("IMAGE_TAG", fallback)

    if not host_value:
        raise SystemExit("ERROR: REGISTRY_HOST is empty in environment and .harbor_env")
    if not project_name:
        raise SystemExit("ERROR: PROJECT_NAME is empty in environment and .harbor_env")
    if not repository_name:
        raise SystemExit("ERROR: REPOSITORY_NAME is empty in environment and .harbor_env")
    if not image_tag:
        raise SystemExit("ERROR: IMAGE_TAG is empty in environment and .harbor_env")

    ctx = ssl._create_unverified_context()
    auth = "Basic " + base64.b64encode(f"{owner_user}:{owner_pass}".encode("utf-8")).decode("ascii")

    repo_path = urllib.parse.quote(repository_name, safe="")
    checks = [
        (f"/api/v2.0/projects/{urllib.parse.quote(project_name, safe='')}/repositories/{repo_path}", "repository"),
        (
            f"/api/v2.0/projects/{urllib.parse.quote(project_name, safe='')}/repositories/{repo_path}/artifacts/{urllib.parse.quote(image_tag, safe='')}",
            "artifact",
        ),
    ]

    for path, kind in checks:
        url = f"https://{host_value}{path}"
        req = urllib.request.Request(url=url, method="GET")
        req.add_header("Authorization", auth)
        try:
            with urllib.request.urlopen(req, context=ctx) as resp:
                if resp.status != 200:
                    raise SystemExit(f"ERROR: Harbor {kind} verification failed with HTTP {resp.status} for {url}")
        except urllib.error.HTTPError as e:
            payload = e.read().decode("utf-8")
            raise SystemExit(f"ERROR: Harbor {kind} verification failed with HTTP {e.code} for {url}. Payload: {payload}")

    print(
        f"Harbor verification passed: https://{host_value}/harbor/projects/{project_name}/repositories/{repository_name}/artifacts-tab"
    )


if __name__ == "__main__":
    main()
