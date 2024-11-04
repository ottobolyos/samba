FROM ubuntu:24.04 AS base

ENV PATH="/container/scripts:$PATH"

# Copy the scripts
COPY . /container/

# Define environment variables using which we determine whether to install various optional programs which can be used with Samba
# Note: By default, we install everything.
ARG AD_INSTALL
ARG AVAHI_INSTALL
ARG WSDD2_INSTALL

ENV AD_INSTALL="${AD_INSTALL:-true}"
ENV AVAHI_INSTALL="${AVAHI_INSTALL:-true}"
ENV WSDD2_INSTALL="${WSDD2_INSTALL:-true}"

# Define environment variables whether the optional propgrams are disabled by default
# Note: By default, they are all enabled unless they are not installed (we make this sure in the build script, as `ENV` does not support dynamic variable definition).
ARG AD_DISABLE
ARG AVAHI_DISABLE
ARG WSDD2_DISABLE

ENV AD_DISABLE="$AD_DISABLE"
ENV AVAHI_DISABLE="$AVAHI_DISABLE"
ENV WSDD2_DISABLE="$WSDD2_DISABLE"

# Define Docker image name
# Note: Example: `servercontainers/samba` for Docker Hub or `ghcr.io/servercontainers/samba` for GitHub Container Registry.
ARG DOCKER_IMAGE_NAME
ENV DOCKER_IMAGE_NAME="$DOCKER_IMAGE_NAME"

# Define source code URL
# Note: Example: `https://github.com/ServerContainers/samba`.
ARG IMAGE_SOURCE_CODE_URL
ENV IMAGE_SOURCE_CODE_URL="$IMAGE_SOURCE_CODE_URL"

RUN DEBIAN_FRONTEND='noninteractive' && \
  apt-get update \
  # Install dependencies
  && apt-get -y install \
    # Base dependencies
    runit samba samba-client \
    $([ "$AVAHI_INSTALL" = 'true' ] && echo -n avahi-daemon) \
    $([ "$AD_INSTALL" = 'true' ] && echo -n \
      adcli \
      krb5-user \
      libnss-winbind \
      libpam-krb5 \
      libpam-winbind \
      realmd \
      samba-common \
      sssd-ad \
      sssd-tools \
      winbind \
    ) \
    $([ "$WSDD2_INSTALL" = 'true' ] && echo -n wsdd2) \
  && if [ "$AVAHI_INSTALL" = 'true' ]; then \
    # Configure Avahi
    sed -i 's/#enable-dbus=.*/enable-dbus=no/g' /etc/avahi/avahi-daemon.conf \
    && rm -vf /etc/avahi/services/* \
    && mkdir -p /external/avahi \
    && touch /external/avahi/not-mounted; \
  else \
    # Remove Avahi configuration when it is not installed
    rm -rf /container/config/avahi /container/config/runit/avahi; \
  fi \
  && ( \
    [ "$AD_INSTALL" = 'true' ] \
      # Configure Active Directory
      && echo -e '[global]\nkrb5_auth = yes\nkrb5_ccache_type = FILE' >> /etc/security/pam_winbind.conf \
      # Remove `winbind` startup script
      || rm -rf /container/config/runit/winbind \
  ) \
  && ( \
    [ "$WSDD2_INSTALL" = 'true' ] \
      # Configure WSDD2 \
      && echo 'No WSDD2 configuration required' \
      # Remove WSDD2 configuration when it is not installed
      || rm -rf /container/config/runit/wsdd2 \
  ) \
  # Clean PIDs and Samba configuration, and the Alpine Linux entrypoint script
  && rm -rf /var/run/samba/* /etc/samba/* scripts/entrypoint.sh \
  # Make use this folder exists
  # Note: When this folder does not exist, Samba/`testparm` would warn that the `lock` and `pid` directory does not exist.
  && mkdir -p /run/samba

VOLUME ["/shares"]

EXPOSE 137/udp 139 445

HEALTHCHECK --interval=60s --timeout=15s CMD smbclient -L //localhost -U %

ENTRYPOINT ["/container/scripts/entrypoint_ubuntu.sh"]

CMD [ "runsvdir", "-P", "/container/config/runit" ]