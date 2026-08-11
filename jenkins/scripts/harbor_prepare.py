import base64
import json
import os
import re
import ssl
import urllib.error
import urllib.parse
import urllib.request


def norm(v: str) -> str:
    if v is None:
        return ""
    vv = str(v).strip()
    if vv.lower() in ("", "null", "none"):
        return ""
    return vv


def read_simple_var(file_path: str, key: str) -> str:
    if not os.path.exists(file_path):
        return ""
    pattern = re.compile(r"^\s*" + re.escape(key) + r"\s*:\s*(.+?)\s*$")
    with open(file_path, "r", encoding="utf-8") as f:
        for line in f:
            m = pattern.match(line)
            if not m:
                continue
            raw = m.group(1).strip()
            if raw.startswith("#"):
                continue
            if (raw.startswith('"') and raw.endswith('"')) or (raw.startswith("'") and raw.endswith("'")):
                raw = raw[1:-1]
            return norm(raw)
    return ""


def infer_harbor_host_from_inventory(file_path: str) -> str:
    if not os.path.exists(file_path):
        return ""
    host_re = re.compile(r"^\s*ansible_host\s*:\s*(.+?)\s*$")
    with open(file_path, "r", encoding="utf-8") as f:
        for line in f:
            m = host_re.match(line)
            if not m:
                continue
            val = m.group(1).strip()
            if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
                val = val[1:-1]
            val = norm(val)
            if not val:
                continue
            if val.startswith("harbor."):
                return val
            return f"harbor.{val}.nip.io"
    return ""


def call(host_value: str, owner_user: str, owner_pass: str, method: str, path: str, body=None):
    url = f"https://{host_value}{path}"
    req = urllib.request.Request(url=url, method=method)
    creds = f"{owner_user}:{owner_pass}".encode("utf-8")
    auth = "Basic " + base64.b64encode(creds).decode("ascii")
    req.add_header("Authorization", auth)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        req.add_header("Content-Type", "application/json")
    else:
        data = None

    ctx = ssl._create_unverified_context()
    try:
        with urllib.request.urlopen(req, data=data, context=ctx) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        return e.code, raw


def main() -> None:
    owner_user = norm(os.getenv("HARBOR_OWNER_USER"))
    owner_pass = norm(os.getenv("HARBOR_OWNER_PASS"))
    project_name = (
        norm(os.getenv("PROJECT_NAME"))
        or norm(os.getenv("CFG_HARBOR_PROJECT_NAME"))
        or read_simple_var("ansible/group_vars/all.yml", "harbor_project_name")
        or "home-infra"
    )
    repository_name = (
        norm(os.getenv("REPOSITORY_NAME"))
        or norm(os.getenv("CFG_HARBOR_REPOSITORY_NAME"))
        or read_simple_var("ansible/group_vars/all.yml", "harbor_repository_name")
        or "infra-api"
    )
    host_value = norm(os.getenv("HARBOR_HOST_OVERRIDE")) or norm(os.getenv("CFG_HARBOR_HOST"))
    repo_override = norm(os.getenv("IMAGE_REPO"))
    image_tag = norm(os.getenv("IMAGE_TAG")) or "latest"

    if not host_value and repo_override:
        host_value = repo_override.split("/")[0]

    if not host_value:
        host_var = read_simple_var("ansible/group_vars/all.yml", "harbor_host")
        if host_var and "{{" not in host_var and "}}" not in host_var:
            host_value = host_var

    if not host_value:
        host_value = infer_harbor_host_from_inventory("ansible/inventory.yml")

    if not host_value:
        raise SystemExit("ERROR: Harbor host is not set. Configure HARBOR_HOST in jenkins-secrets or pass HARBOR_HOST_OVERRIDE/IMAGE_REPO.")
    if not project_name:
        raise SystemExit("ERROR: PROJECT_NAME is empty.")
    if not repository_name:
        raise SystemExit("ERROR: REPOSITORY_NAME is empty.")

    if repo_override:
        dest_repo = repo_override
    else:
        dest_repo = f"{host_value}/{project_name}/{repository_name}"

    code, payload = call(host_value, owner_user, owner_pass, "GET", f"/api/v2.0/projects/{urllib.parse.quote(project_name, safe='')}")
    if code == 404:
        c2, p2 = call(
            host_value,
            owner_user,
            owner_pass,
            "POST",
            "/api/v2.0/projects",
            {"project_name": project_name, "metadata": {"public": "false"}},
        )
        if c2 not in (201, 409):
            raise SystemExit(f"ERROR: Harbor project bootstrap failed with HTTP {c2}. Payload: {p2}")
    elif code != 200:
        raise SystemExit(f"ERROR: Harbor project check failed with HTTP {code}. Payload: {payload}")

    env_lines = [
        f"DEST_REPO={dest_repo}",
        f"REGISTRY_HOST={host_value}",
        f"PROJECT_NAME={project_name}",
        f"REPOSITORY_NAME={repository_name}",
        f"IMAGE_TAG={image_tag}",
    ]
    with open(".harbor_env", "w", encoding="utf-8") as f:
        for line in env_lines:
            print(line, file=f)

    print(f"Pushing image to {dest_repo}:{image_tag}")


if __name__ == "__main__":
    main()
