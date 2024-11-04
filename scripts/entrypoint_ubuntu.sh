#!/usr/bin/env bash

# Dependencies [WIP list]:
# - Bash;
# - GNU `grep`;
# - GNU `sed`;
# - `samba`;
# - `coreutils` (for `env`);
# - `shadow-utils`/`shadow` (for `groupadd`);

# Exit codes:
# 0 - Success
# 1 - Unknown error
# 2 - AD only: One or more required variables are not defined (`$AD_ADMIN_PASS`, `$AD_ADMIN_USER`, `$SAMBA_GLOBAL_CONFIG_realm`
# 3 - AD only: Failed to discover realm
# 4 - AD only: Failed to join realm
# 5 - AD only: Failed to join domain
# 6 - AD only: Failed to register DNS entry for the container to Active Directory

set -euo pipefail

export IFS=$'\n'
INITALIZED='/.initialized'

cat << EOF
################################################################################

Welcome to the $DOCKER_IMAGE_NAME

################################################################################

You'll find this container source code here:

    ${IMAGE_SOURCE_CODE_URL-}

The container repository will be updated regularly.

################################################################################

This image was build using these components:

    AD_INSTALL    = $AD_INSTALL
    AVAHI_INSTALL = $AVAHI_INSTALL
    WSDD2_INSTALL = $WSDD2_INSTALL

################################################################################


EOF

if [ ! -f "$INITALIZED" ]; then
  echo '>> CONTAINER: starting initialisation'

  # Copy the main Samba configuration file
  cp /container/config/samba/smb.conf /etc/samba/smb.conf

  ##
  # MAIN CONFIGURATION
  ##

  if [ -n "${SAMBA_CONF_SERVER_ROLE-}" ]; then
    echo ">> SAMBA CONFIG: \$SAMBA_CONF_SERVER_ROLE set, using '${SAMBA_CONF_SERVER_ROLE}'"
    sed -i 's$standalone server$'"${SAMBA_CONF_SERVER_ROLE}"'$g' /etc/samba/smb.conf
  fi

  if [ -n "${NETBIOS_DISABLE-}" ]; then
    echo '>> SAMBA CONFIG: $NETBIOS_DISABLE is set - disabling nmbd'
    echo 'disable netbios = yes' >> /etc/samba/smb.conf
  fi

  if [ -z "${SAMBA_CONF_LOG_LEVEL-}" ]; then
    SAMBA_CONF_LOG_LEVEL=1
    echo ">> SAMBA CONFIG: no \$SAMBA_CONF_LOG_LEVEL set, using '$SAMBA_CONF_LOG_LEVEL'"
  fi

  echo "log level = $SAMBA_CONF_LOG_LEVEL" >> /etc/samba/smb.conf

  if [ -z "${SAMBA_CONF_MAP_TO_GUEST-}" ]; then
    SAMBA_CONF_MAP_TO_GUEST='Bad User'
    echo ">> SAMBA CONFIG: no \$SAMBA_CONF_MAP_TO_GUEST set, using '$SAMBA_CONF_MAP_TO_GUEST'"
  fi

  echo "map to guest = $SAMBA_CONF_MAP_TO_GUEST" >> /etc/samba/smb.conf

  if [ -z "${SAMBA_CONF_SERVER_STRING-}" ]; then
    SAMBA_CONF_SERVER_STRING='Samba Server'
    echo ">> SAMBA CONFIG: no \$SAMBA_CONF_SERVER_STRING set, using '$SAMBA_CONF_SERVER_STRING'"
  fi

  echo "server string = $SAMBA_CONF_SERVER_STRING" >> /etc/samba/smb.conf

  if [ -z "${SAMBA_CONF_WORKGROUP-}" ]; then
    SAMBA_CONF_WORKGROUP='WORKGROUP'
    echo ">> SAMBA CONFIG: no \$SAMBA_CONF_WORKGROUP set, using '$SAMBA_CONF_WORKGROUP'"
  fi

  echo "workgroup = $SAMBA_CONF_WORKGROUP" >> /etc/samba/smb.conf

  ##
  # GLOBAL CONFIGURATION
  ##

  # Add multiple global configuration defined by user
  sed -z 's/;/\n/g;s/\n\+/\n/g' <<< "${SAMBA_GLOBAL_STANZA-}" >> /etc/samba/smb.conf

  for I_CONF in $(env | grep '^SAMBA_GLOBAL_CONFIG_'); do
    CONF_KEY_VALUE="$(sed 's/^SAMBA_GLOBAL_CONFIG_//g;s/=.*//g;s/_SPACE_/ /g;s/_COLON_/:/g;s/_ASTERISK_/*/g' <<< "$I_CONF")"
    CONF_CONF_VALUE="${I_CONF#*=}"
    echo ">> global config - adding: '$CONF_KEY_VALUE' = '$CONF_CONF_VALUE' to /etc/samba/smb.conf"
    echo "$CONF_KEY_VALUE = $CONF_CONF_VALUE" >> /etc/samba/smb.conf
  done

  ##
  # Create GROUPS
  ##
  for I_CONF in $(env | grep '^GROUP_'); do
    GROUP_NAME="$(sed 's/^GROUP_//g;s/=.*//g' <<< "$I_CONF")"
    GROUP_ID="${I_CONF#*=}"
    echo ">> GROUP: adding group $GROUP_NAME with GID: $GROUP_ID"
    groupadd -g "$GROUP_ID" "$GROUP_NAME"
  done

  for I_ACCOUNT in $(env | grep '^ACCOUNT_'); do
    ##
    # Create USER ACCOUNTS
    ##

    ACCOUNT_NAME="$(sed 's/ACCOUNT_//g; s/^.*$/\L&/' <<< "${I_ACCOUNT%%=*}")"
    ACCOUNT_PASSWORD="${I_ACCOUNT#*=}"
    ACCOUNT_UID="$(env | grep "^UID_$ACCOUNT_NAME" | sed 's/^[^=]*=//g')"

    # Create a new user
    if [ "$ACCOUNT_UID" -gt 0 ] 2>/dev/null; then
      echo ">> ACCOUNT: adding account: $ACCOUNT_NAME with UID: $ACCOUNT_UID"
      useradd -MNu "$ACCOUNT_UID" -s /bin/false "$ACCOUNT_NAME"
    else
      echo ">> ACCOUNT: adding account: $ACCOUNT_NAME"
      useradd -MNs /bin/false "$ACCOUNT_NAME"
    fi

    # Add the user to `smbpasswd` without a password
    smbpasswd -an "$ACCOUNT_NAME"

    if grep -q "^$ACCOUNT_NAME:[0-9]*:.*:$" <<< "$ACCOUNT_PASSWORD"; then
      # Add the hashed password to `smbpasswd`
      echo ">> ACCOUNT: found SMB Password HASH instead of plain-text password"
      CLEAN_HASH="${ACCOUNT_PASSWORD#*:[0-9]*:}"
      sed -i 's/\('"$ACCOUNT_NAME"':[0-9]*:\).*/\1'"$CLEAN_HASH"'/g' /var/lib/samba/private/smbpasswd
    else
      # Hash the plain-text password to `smbpasswd`
      echo -e "$ACCOUNT_PASSWORD\n$ACCOUNT_PASSWORD" | passwd "$ACCOUNT_NAME"
      echo -e "$ACCOUNT_PASSWORD\n$ACCOUNT_PASSWORD" | smbpasswd "$ACCOUNT_NAME"
    fi

    # Enable the user via `smbpasswd`
    smbpasswd -e "$ACCOUNT_NAME"

    ##
    # Add USER ACCOUNTS to GROUPS
    ##

    # Add the user to groups
    ACCOUNT_GROUPS="$(env | grep "^GROUPS_$ACCOUNT_NAME" | sed 's/^[^=]*=//g')"

    for GRP in $(sed -z 's/,/\n/g;s/\n\+/\n/g' <<< "$ACCOUNT_GROUPS"); do
      echo ">> ACCOUNT: adding account: $ACCOUNT_NAME to group: $GRP"
      usermod -aG "$GRP" "$ACCOUNT_NAME"
    done

    # Unset the account name variable
    unset "${I_ACCOUNT%%=*}"
  done

  echo >> /etc/samba/smb.conf

  ##
  # Active Directory configuration
  ##
  if [ "${AD_INSTALL-}" = 'true' ] && [ -n "${AD_DISABLE-}" ]; then
    echo '>> AD: Starting configuration ...'

    # Check whether the required variables are defined
    if [ -z "${AD_ADMIN_PASS-}" ] || [ -z "${AD_ADMIN_USER-}" ] || [ -z "${SAMBA_GLOBAL_CONFIG_realm-}" ]; then
      # shellcheck disable=SC2016 # Expressions don't expand in single quotes, use double quotes for that.
      echo 'ERROR: AD: `$AD_ADMIN_PASS`, `$AD_ADMIN_USER` and `$SAMBA_GLOBAL_CONFIG_realm` must be defined when using Active Directory.' 1>&2
      exit 2
    fi

    echo ">> AD: Checking if the ${SAMBA_GLOBAL_CONFIG_realm-} realm can be discovered ..."

    # Note: `--install /` is required, as otherwise it complains about a missing DBus bus.
    if ! realm --install / -v discover "${SAMBA_GLOBAL_CONFIG_realm-}"; then
      echo "ERROR: AD: Failed to discover the ${SAMBA_GLOBAL_CONFIG_realm-} realm." 1>&2
      exit 3
    fi

    # Join the realm
    # Note: When we have already joined the realm, the exit code is `1`, there we had to use `|| true`.
    echo ">> AD: Joining the \`${SAMBA_GLOBAL_CONFIG_realm-}\` realm ..."
    realm --install / join "${SAMBA_GLOBAL_CONFIG_realm-}" -U "${AD_ADMIN_USER-}" <<< "${AD_ADMIN_PASS-}" || true

    # Check whether we have successfully joined the realm
    is_realm_configured="$(realm --install / -v list "${SAMBA_GLOBAL_CONFIG_realm-}" 2> /dev/null | grep -Po 'configured: \K.*')"

    # shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.
    if [ "$?" != 0 ] || [ "$is_realm_configured" = 'no' ]; then
      echo "ERROR: AD: Failed to join the \`${SAMBA_GLOBAL_CONFIG_realm-}\` realm." 1>&2
      exit 4
    fi

    # Automatically create the home folder after login
    # FIXME: Do we need this? We might also add an option for this, maybe only if there is some kind of `smb.conf` config.
    # pam-auth-update --enable mkhomedir

    # Join the domain
    echo ">> AD: Joining the \`${SAMBA_GLOBAL_CONFIG_realm,,}\` domain ..."
    net ads join -U"${AD_ADMIN_USER-}%${AD_ADMIN_PASS-}"

    # Check whether we have successfully joined the domain
    if ! net ads info &> /dev/null; then
      echo "ERROR: AD: Failed to join the \`${SAMBA_GLOBAL_CONFIG_realm-}\` domain." 1>&2
      exit 5
    fi

    # Register a DNS entry for the container
    if ! net ads dns register -U"${AD_ADMIN_USER-}%${AD_ADMIN_PASS-}"; then
      echo "ERROR: AD: Failed to register DNS entry for the container to Active Directory." 1>&2
      exit 6
    fi

    echo '>> AD: successfully configured'
  fi

  ##
  # AVAHI basic / general configuration
  ##
  if [ "$AVAHI_INSTALL" = 'true' ]; then
    # Copy the Avahi `samba.service` file
    cp /container/config/avahi/samba.service /etc/avahi/services/samba.service

    [ -z "${MODEL-}" ] && MODEL='TimeCapsule'
    sed -i "s/TimeCapsule/$MODEL/g" /etc/samba/smb.conf

    if ! grep -q '<txt-record>model=' /etc/avahi/services/samba.service; then
      # Remove `</service-group>`
      sed -i '/<\/service-group>/d' /etc/avahi/services/samba.service

      echo ">> AVAHI: zeroconf model: $MODEL"
      echo "
   <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=$MODEL</txt-record>
   </service>
  </service-group>" >> /etc/avahi/services/samba.service
    fi
  fi

  ##
  # Samba Volume Config ENVs
  ##
  for I_CONF in $(env | grep '^SAMBA_VOLUME_CONFIG_' | cut -d= -f1); do
    CONF_VALUE="${!I_CONF}"
    # shellcheck disable=SC2001 # See if you can use ${variable// search/ replace} instead
    CONF_PARSED="$(sed 's/\s*;\s*/\n/g;s/\n\+/\n/g;s/^\s*//' <<< "$CONF_VALUE")"
    VOL_NAME="$(grep -Po '^\[\K[^\]]+' <<< "$CONF_PARSED")"

    # Check if `$VOL_NAME` is set to a non-empty string, else log a warning and continue with the next loop
    if [ -z "$VOL_NAME" ]; then
      echo "WARNING: Volume name \`$VOL_NAME\` (from \`$I_CONF\`) is set to an empty string, skipping its configuration." 1>&2
      continue
    fi

    VOL_PATH="$(grep -Po '^path *= *\K.*$' <<< "$CONF_PARSED")"

    # Check if `$VOL_PATH` is an existing folder, else log a warning and continue with the next loop
    if [ -z "$VOL_PATH" ] || [ ! -d "$VOL_PATH" ]; then
      echo "WARNING: Volume path \`$VOL_PATH\` (from \`$I_CONF\`) is either not defined, does not exist or is not a folder, skipping its configuration." 1>&2
      continue
    fi

    # Warn if `VOL_PATH` is not available under `/shares`
    if [[ "$VOL_PATH" != /shares/* ]]; then
      echo "WARNING: Volume $VOL_PATH is not available under \`/shares\` folder. Consider moving it there." 1>&2
    fi

    echo ">> VOLUME: adding volume: $VOL_NAME (path=$VOL_PATH)"

    # Check whether `I_CONF` contains the configuration for the TimeMachine volume
    if grep -q '^fruit:time machine *= *yes$' <<< "$CONF_CONF_VALUE"; then
      # Remove `</service-group>` only if this is the first time a TimeMachine volume was added
      [ "$AVAHI_INSTALL" = 'true' ] && (grep -q '<txt-record>dk' /etc/avahi/services/samba.service || sed -i '/<\/service-group>/d' /etc/avahi/services/samba.service)

      echo "  >> TIMEMACHINE: adding volume to zeroconf: $VOL_NAME"

      if ! grep -q '%U$' <<< "$VOL_PATH"; then
        echo '  >> TIMEMACHINE: fix permissions (only last one wins; for multiple users I recommend using multi-user mode - see README.md)'
        VALID_USERS="$(grep -Po 'valid users *= *\K.*$' <<< "$CONF_PARSED")"

        for user in $VALID_USERS; do
          echo "  user: $user"
          chown -R "$user.$user" "$VOL_PATH"
        done

        chmod 700 -R "$VOL_PATH"
      fi

      [ -n "$NUMBER" ] && NUMBER="$((NUMBER + 1))"
      [ -z "$NUMBER" ] && NUMBER=0

      if [ "$AVAHI_INSTALL" = 'true' ] && ! grep -q '<txt-record>dk' /etc/avahi/services/samba.service; then
        # For the first time, add complete service
        echo '
 <service>
  <type>_adisk._tcp</type>
  <txt-record>sys=waMa=0,adVF=0x100</txt-record>
  <txt-record>dk'"$NUMBER"'=adVN='"$VOL_NAME"',adVF=0x82</txt-record>
 </service>
</service-group>' >> /etc/avahi/services/samba.service
      else
        # from the second one only append new txt-record
        REPLACE_ME="$(grep '<txt-record>dk' /etc/avahi/services/samba.service | tail -n 1)"
        sed -i 's;'"$REPLACE_ME"';'"$REPLACE_ME"'\n  <txt-record>dk'"$NUMBER"'=adVN='"$VOL_NAME"',adVF=0x82</txt-record>;g' /etc/avahi/services/samba.service
      fi
    fi

    # shellcheck disable=SC2001 # See if you can use ${variable// search/ replace} instead
    sed 's/;/\n/g' <<< "$CONF_VALUE" >> /etc/samba/smb.conf

    if echo "$CONF_VALUE" | sed 's/;/\n/g' | grep 'fruit:time machine' | grep yes &> /dev/null; then
        echo "  >> TIMEMACHINE: adding samba timemachine specifics to volume config: $VOL_NAME ($VOL_PATH)"
        echo ' fruit:metadata = stream
 durable handles = yes
 kernel oplocks = no
 kernel share modes = no
 posix locking = no
 ea support = yes
 inherit acls = yes
' >> /etc/samba/smb.conf
    fi

    if grep -q '%U$' <<< "$VOL_PATH"; then
      VOL_PATH_BASE="$(grep -Po '^.*(?=\/%U$)' <<< "$VOL_PATH")"
      echo "  >> multiuser volume - $VOL_PATH"
      echo ' root preexec = /container/scripts/samba_create_user_dir.sh '"$VOL_PATH_BASE"' %U' >> /etc/samba/smb.conf
    fi

    echo >> /etc/samba/smb.conf

  done

  if [ "$AVAHI_INSTALL" = 'true' ]; then
    if [ -n "${AVAHI_NAME-}" ]; then
      echo ">> ZEROCONF: custom avahi samba.service name: $AVAHI_NAME" && sed -i 's/%h/'"$AVAHI_NAME"'/g' /etc/avahi/services/samba.service
      echo ">> ZEROCONF: custom avahi avahi-daemon.conf host-name: $AVAHI_NAME" && sed -i "s/#host-name=foo/host-name=$AVAHI_NAME/" /etc/avahi/avahi-daemon.conf
    fi

    echo '>> ZEROCONF: samba.service file'
    echo '############################### START ####################################'
    cat /etc/avahi/services/samba.service
    echo '################################ END #####################################'
  fi

  [ -n "${WSDD2_PARAMETERS-}" ] && echo ">> WSDD2: custom parameters for wsdd2 daemon: wsdd2 $WSDD2_PARAMETERS" && sed -i 's/wsdd2/wsdd2 '"$WSDD2_PARAMETERS"'/g' /container/config/runit/wsdd2/run

  [ -n "${NETBIOS_DISABLE-}" ] && echo '>> NETBIOS - DISABLED' && rm -rf /container/config/runit/nmbd

  if [ "$AVAHI_INSTALL" = 'true' ] && [ -z "$AVAHI_DISABLE" ] && [ ! -f '/external/avahi/not-mounted' ]; then
    echo ">> EXTERNAL AVAHI: found external avahi, now maintaining avahi service file 'samba.service'"
    echo '>> EXTERNAL AVAHI: internal avahi gets disabled'
    rm -rf /container/config/runit/avahi
    cp /etc/avahi/services/samba.service /external/avahi/samba.service
    chmod a+rw /external/avahi/samba.service
    echo '>> EXTERNAL AVAHI: list of services'
    ls -l /external/avahi/*.service
  fi

  echo
  echo ">> SAMBA: check smb.conf file using 'testparm -s'"
  echo '############################### START ####################################'
  testparm -s
  echo '############################### END ####################################'
  echo

  echo
  echo '>> SAMBA: print whole smb.conf'
  echo '############################### START ####################################'
  cat /etc/samba/smb.conf
  echo '############################### END ####################################'
  echo

  touch "$INITALIZED"
else
  echo '>> CONTAINER: already initialized - direct start of samba'
fi

##
# CMD
##
echo '>> CMD: exec docker CMD'

echo "$*"
exec "$@"
