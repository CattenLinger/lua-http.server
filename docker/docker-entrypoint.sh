#!/usr/bin/env sh
set -e

printf "Work directory: %s\n" "$(pwd)"

if [ -d /docker-entrypoint.d ]; then
  for script in $(find /docker-entrypoint.d -name "*.env" | sort) ; do
    printf "==== Apply environments: %s\n" "$script"
    . "$script"
  done

  for script in $(find /docker-entrypoint.d -name "*.sh" | sort) ; do
    printf "==== Apply script: %s\n" "$script"
    sh "$script"
  done
fi

launch_params() {
  exec "$@"
}

launch_default() {
  if [ -n "$EXEC_CMD" ]; then
    echo "Currently nothing is configured (EXEC_CMD=${EXEC_CMD})."
    exit 1
  fi
  exec "$EXEC_CMD"
}

if [ -z "$1" ]; then
  launch_default
else
  launch_params "$@"
fi