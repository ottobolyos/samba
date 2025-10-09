#!/usr/bin/env bash

set -euo pipefail

folder="${1-}"
user="${2-}"

if [ ! -e "$folder/$user" ]; then
  mkdir -p "$folder/$user"
  chown "$user:$(id -g "$user")" "$folder/$user"
  chmod -R 700 "$folder/$user"
fi

exit 0
