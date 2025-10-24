# MTLS Conflict on Host (Raspberry OS, Rasbian)

If you are already running Samba/Avahi on your Docker host (or you're wanting to run this on your NAS),
you should be aware that using --net=host will cause a conflict with the Samba/Avahi install.

Raspberry Pi users: be aware that there is already an mDNS responder running on the stock Raspberry Pi OS
image that will conflict with the mDNS responderin the container.

I've added a way to instruct the container to use the external host avahi by mounting `/external/avahi`
more infos about it here: https://github.com/ServerContainers/samba#volumes
this way the container will not start the avahi daemon/mtls service and place the service file into the mounted folder.

More comments/infos: https://github.com/ServerContainers/samba/issues/79


# Problems with macOS and Windows / Docker Desktop

You might run into troubles on macOS (confirmed) and maybe even Windows (I suspect there might me similar issues).

It seems to me, that the filesystem mounts from the host to the container e.g. samba have problems with permissons etc.

One user couldn't delete files on the share he mounted from his macbook. I retried this on a macbook and wasn't even able to create files.

More comments/infos: https://github.com/ServerContainers/samba/issues/125

# macOS Finder - you see the Server with the specified AVAHI Name and also with the Docker Host hostname

It's NetBIOS on port 445 that advertises using the DNS hostname of the server.

If you sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.netbiosd.plist on the Mac, the 'PC' will immediately disappear from Network. If you run sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.netbiosd.plist it will come back after 15-30 seconds or so. Tested this twice.

So the solution seems to be to add 'NETBIOS_DISABLE: 1' to the samba docker environment and then also unload and re-load the netbios plist on the Mac using the above two commands. This is because the previously discovered NetBIOS services seem to be a bit sticky and don't drop off (and flushing the DNS cache doesn't flush those at all.) It's been 10min+ now and it hasn't come back yet (even after docker LXC restart).

Reading:
https://www.oreilly.com/openbook/samba/book/ch04_04.html
https://support.apple.com/en-us/102050

See Issue: https://github.com/ServerContainers/samba/issues/135

# Secure Computing Mode (`seccomp`) and `realm`/`adcli` in Samba with AD

When using Active Directory with this container, `realm`/`adcli` commands require specific system calls and capabilities that may be blocked by Docker's default seccomp profile.

## Required Capabilities

- `SYS_ADMIN` - Required for `clone` and `clone3` system calls
- `SYS_CHROOT` - Required for `chroot` system call

## The Socket Syscall Issue

The main issue is with the `socket` syscall. Docker's [default seccomp profile](https://github.com/moby/moby/blob/master/profiles/seccomp/default.json) allows `socket`, but only when the first argument is not `40` (AF_ALG).

However, `realm`/`adcli` uses `socket` with `AF_UNIX` (value `1`), which is blocked. This causes realm join operations to fail.

## Solutions

### Option 1: Disable seccomp (Easier, Less Secure)

> [!Warning]
> Only use this approach if you cannot upgrade `libseccomp` on your host. For example, Ubuntu 20.04 ships with `libseccomp v2.5.1`, but `close_range` syscall support (required by `realm`/`adcli`) was added in `v2.5.2`.

**Docker CLI:**
```bash
docker run --security-opt seccomp=unconfined ...
```

**Docker Compose:**
```yaml
services:
  samba:
    # ...
    security_opt:
      - seccomp=unconfined
```

### Option 2: Custom Seccomp Profile (Preferred)

> [!Note]
> Seccomp profiles must be specified at container runtime, not at image build time.

**Steps:**

1. Download Docker's default seccomp profile:
   ```bash
   curl -o custom_seccomp.json https://raw.githubusercontent.com/moby/moby/master/profiles/seccomp/default.json
   ```

2. Edit the file and find the `socket` syscall entry (search for `"names": ["socket"]`)

3. Remove the `args` array from that entry so it looks like:
   ```json
   {
     "names": ["socket"],
     "action": "SCMP_ACT_ALLOW"
   }
   ```

4. Use the custom profile:

   **Docker CLI:**
   ```bash
   docker run --security-opt seccomp="$PWD/custom_seccomp.json" ...
   ```

   **Docker Compose:**
   ```yaml
   services:
     samba:
       # ...
       security_opt:
         - seccomp=./custom_seccomp.json
   ```

### Advanced: Discovering Required Syscalls

If you need to identify other required syscalls, use the SystemTap [`container_check.stp`](https://sourceware.org/git/gitweb.cgi?p=systemtap.git;a=blob;f=testsuite/systemtap.examples/profiling/container_check.stp) script.

**Requirements:**
- `systemtap` package
- `linux-headers-$(uname -r)` (Ubuntu) or `kernel-devel` (RHEL)
- `linux-image-$(uname -r)-dbgsym` (Ubuntu) - see [setup guide](https://askubuntu.com/a/197057/279745)
- `strace`

**Usage:**
```bash
./container_check.stp -DKRETACTIVE=100 -c 'sudo strace -c -f your-command-here'
```

See also:
- [Red Hat article on container capabilities](https://developers.redhat.com/blog/2017/02/16/find-what-capabilities-an-application-requires-to-successful-run-in-a-container)
- [SystemTap Beginners Guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/systemtap_beginners_guide/index)

---

# Leaving a Realm

## Known Issue with `realm leave`

When using `realm leave` to leave an AD realm, it modifies `/etc/samba/smb.conf`:

- Removes `realm` and `workgroup` settings
- Changes `security` to `user`

**Problem:** When rejoining with `realm join`, these settings are not restored. While `realm join` succeeds, the incomplete `smb.conf` causes `net ads join` to fail and breaks `smbd`/`nmbd`/`winbind` functionality.

**Workaround:** Manually restore the AD-specific settings in `smb.conf` after rejoining, or recreate the container to reset to the proper AD configuration.
# SMB Authentication Errors with Remote Winbind Proxy

When using the remote winbind proxy feature (WINBIND_DISABLE + WINBIND_SERVER) to run Samba containers on isolated Docker networks, you may encounter authentication errors from Windows clients.

## Error 1311: "Domain not available"

### Symptoms

Windows clients can connect by IP address but get this error:
```
System error 1311 has occurred.
We can't sign you in with this credential because your domain isn't available.
Make sure your device is connected to your organization's network and try again.
```

SMB container logs show:
```
WARNING: Failed to create BUILTIN\Administrators group! Can Winbind allocate gids?
WARNING: Failed to create BUILTIN\Users group! Can Winbind allocate gids?
```

### Root Cause

The `smbd` daemon started before the winbind-tunnel Unix socket was fully established. Even though the TCP connection to the remote winbind server was verified, the local Unix socket at `/var/run/samba/winbindd/pipe` hadn't been created yet.

This timing issue caused smbd to fail group allocation, preventing Windows clients from authenticating.

### How It's Fixed

The SMB container now includes automatic synchronization:

1. **config/runit/winbind-tunnel/run** - Verifies socat successfully creates the Unix socket
   - Starts socat in background and captures PID
   - Waits up to 10 seconds for socket creation
   - Verifies socat is still running after socket appears
   - Monitors socat and allows runit to restart if it dies

2. **config/runit/samba/run** - Waits for socket before starting smbd
   - Checks if remote winbind proxy is configured
   - Waits up to 60 seconds for Unix socket to exist
   - Only then starts smbd
   - Ensures group allocation succeeds immediately

### Verification Steps

Check that the winbind proxy is working:

```bash
# Verify socat is running in SMB container
docker exec samba-container ps aux | grep socat
# Expected: socat UNIX-LISTEN:/var/run/samba/winbindd/pipe...

# Verify Unix socket exists
docker exec samba-container ls -la /var/run/samba/winbindd/pipe
# Expected: srwxrwxrwx ... /var/run/samba/winbindd/pipe

# Test user resolution via winbind proxy
docker exec samba-container getent passwd username
# Expected: username:*:10000:10000:User Name:/home/username:/bin/bash

# Test group resolution
docker exec samba-container getent group groupname
# Expected: groupname:*:10001:user1,user2,user3
```

If these commands work, the winbind proxy is functioning correctly.

### If Problem Persists

1. **Check kerberos container** - Verify winbind is running:
   ```bash
   docker exec kerberos-container service winbind status
   docker exec kerberos-container wbinfo -u  # List AD users
   docker exec kerberos-container wbinfo -t  # Test trust
   ```

2. **Check TCP proxy** - Verify socat is exposing winbind on port 9999:
   ```bash
   docker exec kerberos-container ps aux | grep socat
   docker exec kerberos-container netstat -tulpn | grep 9999
   ```

3. **Check network connectivity** - Verify SMB can reach kerberos:
   ```bash
   docker exec samba-container nc -zv kerberos-server 9999
   ```

4. **Check environment variables** - Both must be set:
   ```bash
   docker exec samba-container env | grep WINBIND
   # Expected:
   # WINBIND_DISABLE=true
   # WINBIND_SERVER=kerberos-server
   # WINBIND_PORT=9999
   ```

## Error 53: "Network path not found"

### Symptoms

Windows clients cannot connect using the hostname:
```powershell
PS> net use Z: \\tooling.wooddale.tempco.com\tooling
System error 53 has occurred.
The network path was not found.
```

But connection by IP address may work (though it triggers Error 1311 if winbind proxy has issues).

### Root Cause

The hostname `tooling.wooddale.tempco.com` is not resolving to the correct IP address for Windows clients. This happens when:

1. **DNS registration failed** - The container didn't register in AD DNS
2. **Wrong IP registered** - The kerberos container registered its own IP instead of the SMB container's client-facing IP
3. **HOST_IP/HOST_HOSTNAME not set** - Environment variables missing or incomplete

### Solution

Configure the kerberos container to register the SMB container's client-facing IP address in AD DNS:

```yaml
services:
  kerberos:
    environment:
      # BOTH must be set together
      HOST_IP: "172.23.0.3"  # SMB container's client-facing IP
      HOST_HOSTNAME: "tooling.wooddale.tempco.com"
```

**Important:** The IP address should be the SMB container's **client-facing network interface** IP, not the internal network used for winbind proxy communication.

### Verification Steps

1. **Check DNS resolution** from Windows client:
   ```powershell
   nslookup tooling.wooddale.tempco.com
   # Should return: 172.23.0.3 (SMB container's client-facing IP)
   ```

2. **Test network connectivity**:
   ```powershell
   ping tooling.wooddale.tempco.com
   Test-NetConnection -ComputerName tooling.wooddale.tempco.com -Port 445
   ```

3. **Check kerberos container logs** for DNS registration:
   ```bash
   docker logs kerberos-container 2>&1 | grep -i dns
   # Expected: "Successfully registered hostname with DNS"
   ```

4. **Verify AD DNS record** (from domain controller or kerberos container):
   ```bash
   nslookup tooling.wooddale.tempco.com
   # Should show: Address: 172.23.0.3
   ```

### If Problem Persists

1. **Check environment variables** in kerberos container:
   ```bash
   docker exec kerberos-container env | grep HOST
   # Expected:
   # HOST_IP=172.23.0.3
   # HOST_HOSTNAME=tooling.wooddale.tempco.com
   ```

2. **Manually register in AD DNS** (temporary workaround):
   ```bash
   docker exec kerberos-container net ads dns register tooling.wooddale.tempco.com 172.23.0.3
   ```

3. **Check SMB container network configuration**:
   ```bash
   docker inspect samba-container | jq '.[].NetworkSettings.Networks'
   # Verify the client-facing network has IP 172.23.0.3
   ```

4. **Use hosts file** for testing (Windows client):
   ```
   # C:\Windows\System32\drivers\etc\hosts
   172.23.0.3  tooling.wooddale.tempco.com tooling
   ```

## Common Mistakes

### 1. Starting smbd before winbind socket ready

**Symptom:** Error 1311 even though socat is running

**Cause:** Old versions didn't wait for socket creation

**Fix:** Update to latest image with automatic socket synchronization (config/runit/samba/run waits for socket)

### 2. Wrong HOST_IP value

**Symptom:** Error 53, DNS resolves to wrong IP

**Cause:** Used kerberos container's IP or internal network IP instead of SMB container's client-facing IP

**Fix:** Set HOST_IP to the SMB container's client-facing network interface IP

### 3. Only one of HOST_IP/HOST_HOSTNAME set

**Symptom:** Kerberos container log shows warning about incomplete configuration

**Fix:** Both environment variables must be set together, or both must be unset

### 4. Containers on different Docker networks

**Symptom:** SMB container can't reach kerberos:9999

**Cause:** No shared network between kerberos and samba containers

**Fix:** Ensure both containers are on at least one common Docker network

### 5. Missing shared keytab

**Symptom:** Authentication fails even with working winbind proxy

**Cause:** SMB container can't decrypt Kerberos tickets

**Fix:** Mount kerberos container's keytab to SMB container:
```yaml
samba:
  volumes:
    - kerberos-config:/etc/krb5:ro
```

## Advanced Debugging

### Check smbd logs for winbind errors

```bash
docker exec samba-container tail -f /var/log/samba/log.smbd
```

Look for:
- "Failed to connect to winbind"
- "Domain not available"
- "User not found"
- "Group not found"

### Monitor winbind-tunnel service

```bash
# Check service status
docker exec samba-container sv status winbind-tunnel

# View service logs
docker logs samba-container 2>&1 | grep -i winbind
```

### Test winbind functionality directly

From kerberos container:
```bash
# List AD users
wbinfo -u

# List AD groups
wbinfo -g

# Test trust with AD
wbinfo -t

# Get user info
wbinfo -i username
```

From SMB container (via proxy):
```bash
# Same commands should work via proxy
getent passwd username
getent group groupname
id username
```

If kerberos container commands work but SMB container commands fail, the winbind proxy connection is broken.

---

## LDAP Authentication Issues

### Container exits with code 7

**Symptom:** Container fails to start with exit code 7 and error message about LDAP

**Possible causes:**

1. **Both LDAP and Active Directory enabled**
   - **Error:** `ERROR: LDAP: Cannot enable both LDAP and Active Directory authentication simultaneously.`
   - **Cause:** Both `LDAP_ENABLE` and Active Directory (via `AD_INSTALL` without `AD_DISABLE`) are enabled
   - **Fix:** Choose one authentication backend - either LDAP or Active Directory, not both

2. **Missing LDAP_ADMIN_PASSWORD**
   - **Error:** `ERROR: LDAP: $LDAP_ADMIN_PASSWORD must be defined when LDAP support is enabled.`
   - **Fix:** Set the `LDAP_ADMIN_PASSWORD` environment variable

3. **smbpasswd command failed**
   - **Error:** `ERROR: LDAP: Failed to configure admin credentials in secrets.tdb`
   - **Cause:** Permissions issue, corrupted Samba installation, or smb.conf syntax error
   - **Fix:** Check smb.conf syntax with `testparm -s`, verify `/var/lib/samba/private` exists

### LDAP bind failures

**Symptom:** Container starts but Samba can't authenticate users, logs show LDAP bind errors

**Debugging steps:**

1. **Verify LDAP server connectivity:**
   ```bash
   docker exec samba-container ldapsearch -x -H ldap://your-ldap-server -D "cn=admin,dc=example,dc=com" -W -b "dc=example,dc=com"
   ```

2. **Check LDAP configuration in smb.conf:**
   ```bash
   docker exec samba-container testparm -s | grep ldap
   ```

   Should show:
   ```
   passdb backend = ldapsam:ldap://your-ldap-server
   ldap admin dn = cn=admin,dc=example,dc=com
   ldap suffix = dc=example,dc=com
   ```

3. **Verify secrets.tdb contains LDAP password:**
   ```bash
   docker exec samba-container tdbdump /var/lib/samba/private/secrets.tdb | grep LDAP_BIND_PW
   ```

   Should show a key like:
   ```
   key(XX) = "SECRETS/LDAP_BIND_PW/cn=admin,dc=example,dc=com"
   ```

4. **Check Samba logs for LDAP errors:**
   ```bash
   docker exec samba-container tail -f /var/log/samba/log.smbd
   ```

   Look for:
   - `ldap_bind: Invalid credentials` - Wrong LDAP_ADMIN_PASSWORD
   - `ldap_connect_system: Failed to retrieve password` - secrets.tdb not configured
   - `Connection refused` - LDAP server not accessible

### Common LDAP configuration mistakes

1. **Wrong LDAP admin DN**
   - **Symptom:** `ldap_bind: Invalid DN syntax`
   - **Fix:** Verify the DN format matches your LDAP schema: `cn=admin,dc=example,dc=com`

2. **LDAP server not accessible from container**
   - **Symptom:** `Can't contact LDAP server`
   - **Fix:** Use IP address instead of hostname, or ensure DNS resolution works inside container
   - **Test:** `docker exec samba-container ping ldap.example.com`

3. **Missing ldap suffix configuration**
   - **Symptom:** `No such object` errors in logs
   - **Fix:** Set `SAMBA_GLOBAL_CONFIG_ldap_SPACE_suffix` to your base DN

4. **SSL/TLS issues**
   - **Symptom:** `TLS handshake failed` or `certificate verify failed`
   - **Fix:** Either:
     - Use `ldap://` instead of `ldaps://` for testing
     - Set `SAMBA_GLOBAL_CONFIG_ldap_SPACE_ssl: "off"` for testing
     - Mount proper CA certificates if using SSL
     - Set `SAMBA_GLOBAL_CONFIG_ldap_SPACE_ssl: "start_tls"` for STARTTLS

### Password rotation

LDAP admin password is configured on every container start (not just first start). To rotate the password:

1. Change password in LDAP server
2. Update `LDAP_ADMIN_PASSWORD` environment variable
3. Restart the container: `docker restart samba-container`
4. Verify new password is stored: Check container logs for `>> LDAP: successfully configured`

### Verifying LDAP authentication works

Test LDAP user authentication:

```bash
# List users from LDAP
docker exec samba-container pdbedit -L

# Should show users from LDAP directory, not local smbpasswd

# Test SMB authentication with LDAP user
smbclient //localhost/shared -U ldapuser%password
```

If `pdbedit -L` returns empty or shows errors, LDAP integration is not working correctly.
