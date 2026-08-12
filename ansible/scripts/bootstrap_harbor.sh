#!/usr/bin/env bash
set -euo pipefail

# Usage: bootstrap_harbor.sh <harbor_host> <project_name> <harbor_user> <harbor_pass> <harbor_email>
HARBOR_HOST="${1:?}"
PROJECT_NAME="${2:?}"
HARBOR_USER="${3:?}"
HARBOR_PASS="${4:?}"
HARBOR_EMAIL="${5:-kobeep@local.invalid}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "INFO =>: **kubectl is not installed or not in PATH**" >&2
  exit 2
fi

ADMIN_PASS="$(kubectl -n harbor get secret harbor-core -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 --decode)"

for _ in $(seq 1 30); do
  code="$(curl -ks -o /dev/null -w '%{http_code}' -u "admin:${ADMIN_PASS}" "https://${HARBOR_HOST}/api/v2.0/projects")"
  if [ "$code" = "200" ]; then
    break
  fi
  sleep 5
done

user_json="$(curl -ks -u "admin:${ADMIN_PASS}" "https://${HARBOR_HOST}/api/v2.0/users/search?username=${HARBOR_USER}")"
user_id="$(printf '%s' "$user_json" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d[0]["user_id"] if d else "")')"

if [ -z "$user_id" ]; then
  create_user_code="$(curl -ks -o /tmp/harbor_user_create.out -w '%{http_code}' -u "admin:${ADMIN_PASS}" -H 'Content-Type: application/json' -X POST "https://${HARBOR_HOST}/api/v2.0/users" -d "{\"username\":\"${HARBOR_USER}\",\"password\":\"${HARBOR_PASS}\",\"realname\":\"Kobeep\",\"email\":\"${HARBOR_EMAIL}\",\"comment\":\"home_infra owner\"}")"
  if [ "$create_user_code" != "201" ] && [ "$create_user_code" != "409" ]; then
    cat /tmp/harbor_user_create.out
    echo "INFO =>: **Failed to create harbor user ${HARBOR_USER} (code ${create_user_code})**" >&2
    exit 1
  fi
  user_json="$(curl -ks -u "admin:${ADMIN_PASS}" "https://${HARBOR_HOST}/api/v2.0/users/search?username=${HARBOR_USER}")"
  user_id="$(printf '%s' "$user_json" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d[0]["user_id"] if d else "")')"
fi

project_code="$(curl -ks -o /dev/null -w '%{http_code}' -u "admin:${ADMIN_PASS}" "https://${HARBOR_HOST}/api/v2.0/projects/${PROJECT_NAME}")"
if [ "$project_code" = "404" ]; then
  create_project_code="$(curl -ks -o /tmp/harbor_project_create.out -w '%{http_code}' -u "admin:${ADMIN_PASS}" -H 'Content-Type: application/json' -X POST "https://${HARBOR_HOST}/api/v2.0/projects" -d "{\"project_name\":\"${PROJECT_NAME}\",\"metadata\":{\"public\":\"false\"}}")"
  if [ "$create_project_code" != "201" ] && [ "$create_project_code" != "409" ]; then
    cat /tmp/harbor_project_create.out
    echo "INFO =>: **Failed to create harbor project ${PROJECT_NAME} (code ${create_project_code})**" >&2
    exit 1
  fi
fi

project_json="$(curl -ks -u "admin:${ADMIN_PASS}" "https://${HARBOR_HOST}/api/v2.0/projects?name=${PROJECT_NAME}")"
project_id="$(printf '%s' "$project_json" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d[0]["project_id"] if d else "")')"
if [ -z "$project_id" ] || [ -z "$user_id" ]; then
  echo "INFO =>: **Unable to resolve Harbor project_id/user_id during bootstrap**" >&2
  exit 1
fi

member_json="$(curl -ks -u "admin:${ADMIN_PASS}" "https://${HARBOR_HOST}/api/v2.0/projects/${project_id}/members?page_size=100")"
member_exists="$(printf '%s' "$member_json" | python3 -c 'import sys, json; user=sys.argv[1]; d=json.load(sys.stdin); print("yes" if any((x.get("entity_name") == user) for x in d) else "no")' "$HARBOR_USER")"
if [ "$member_exists" = "no" ]; then
  add_member_code="$(curl -ks -o /tmp/harbor_member_add.out -w '%{http_code}' -u "admin:${ADMIN_PASS}" -H 'Content-Type: application/json' -X POST "https://${HARBOR_HOST}/api/v2.0/projects/${project_id}/members" -d "{\"role_id\":2,\"member_user\":{\"user_id\":${user_id}}}")"
  if [ "$add_member_code" != "201" ] && [ "$add_member_code" != "409" ]; then
    cat /tmp/harbor_member_add.out
    echo "INFO =>: **Failed to add member ${HARBOR_USER} to project ${PROJECT_NAME} (code ${add_member_code})**" >&2
    exit 1
  fi
fi

echo "Harbor bootstrap completed for ${HARBOR_HOST} (project ${PROJECT_NAME})"
