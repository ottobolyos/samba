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