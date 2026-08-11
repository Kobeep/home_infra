import base64
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request


def main() -> None:
    owner_user = os.getenv("HARBOR_OWNER_USER", "")
    owner_pass = os.getenv("HARBOR_OWNER_PASS", "")
    host_value = os.getenv("REGISTRY_HOST", "")
    project_name = os.getenv("PROJECT_NAME", "")
    repository_name = os.getenv("REPOSITORY_NAME", "")
    image_tag = os.getenv("IMAGE_TAG", "")

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
