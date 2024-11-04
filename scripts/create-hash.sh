#!/usr/bin/env bash

set -euo pipefail

# Replace original smb config
cp /container/config/samba/smb.conf /etc/samba/smb.conf

read -rp '>> Enter username: ' USERNAME
read -srp '>> New password: ' PASSWORD_1
read -srp "$(printf '\n>> Retype password: ')" PASSWORD_2

USERNAME=$(tr '[:upper:]' '[:lower:]' <<< "$USERNAME")

if [ "$PASSWORD_1" == "$PASSWORD_2" ] && [ "$PASSWORD_1" != '' ]; then
  useradd -Ms /bin/false "$USERNAME" &> /dev/null
  smbpasswd -an "$USERNAME" &> /dev/null
  usermod --password "$PASSWORD_1" "$USERNAME" &> /dev/null
  printf "$PASSWORD_1\n$PASSWORD_1\n" | smbpasswd -s "$USERNAME" &> /dev/null
  grep "^$USERNAME:[0-9]*:.*:$" /var/lib/samba/private/smbpasswd
  exit 0
fi

exit 1
