#!/usr/bin/env bash
set -Eeuo pipefail

command -v docker >/dev/null 2>&1 || {
  printf 'Docker CLI is required to run the image.\n' >&2
  exit 1
}
[[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]] || {
  printf 'Run this target with bazel run, not by invoking the script directly.\n' >&2
  exit 1
}
image_archive="${1:-}"
[[ -n "$image_archive" ]] || {
  printf 'Bazel did not pass the built image archive to this launcher.\n' >&2
  exit 1
}
shift
[[ -r "$image_archive" ]] || {
  printf 'Built image archive not found: %s\n' "$image_archive" >&2
  exit 1
}

device_args=()
group_args=()
declare -A seen_groups=()
found_render=0

case "${1:-all}" in
  help|-h|--help)
    ;;
  *)
    [[ -n "${LLAMA_API_KEY:-}" ]] || {
      printf 'Set and export LLAMA_API_KEY to a strong key before running this target.\n' >&2
      exit 1
    }

    for device in /dev/dri/renderD*; do
      [[ -c "$device" ]] || continue
      found_render=1
      device_args+=(--device "$device:$device:rwm")
      gid="$(stat -c '%g' "$device")"
      if [[ -z "${seen_groups[$gid]:-}" ]]; then
        group_args+=(--group-add "$gid")
        seen_groups[$gid]=1
      fi
    done

    if ((found_render == 0)); then
      printf 'No GPU render devices found under /dev/dri.\n' >&2
      printf 'Pass the host GPU device into Docker before running this target.\n' >&2
      exit 1
    fi

    if [[ -c /dev/kfd ]]; then
      device_args+=(--device /dev/kfd:/dev/kfd:rwm)
      gid="$(stat -c '%g' /dev/kfd)"
      if [[ -z "${seen_groups[$gid]:-}" ]]; then
        group_args+=(--group-add "$gid")
        seen_groups[$gid]=1
      fi
    fi
    ;;
esac

docker load --input "$image_archive"

port="${PORT:-8080}"
if (($# == 0)); then
  set -- all
fi

docker_args=(--rm)
if [[ -t 0 && -t 1 ]]; then
  docker_args+=(--interactive --tty)
fi

exec docker run "${docker_args[@]}" \
  "${device_args[@]}" \
  "${group_args[@]}" \
  --publish "127.0.0.1:$port:$port" \
  --env HOST=0.0.0.0 \
  --env PORT="$port" \
  --env LLAMA_API_KEY \
  --volume qwen-build:/root/.local/share/qwen-local \
  --volume qwen-models:/root/models/qwen3.8-27b \
  llama-qwen:latest "$@"
