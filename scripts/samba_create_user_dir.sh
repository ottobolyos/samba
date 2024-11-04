#!/usr/bin/env bash

set -euo pipefail

folder="${1-}"
user="${2-}"

if [ ! -e "$folder/$user" ]; then
  mkdir -p "$folder/$user"
  chown "$user:$(id -g "$user")" "$user/$folder"
  chmod -R 700 "$user/$folder"
fi

exit 0
