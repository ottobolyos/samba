# still under construction

# samba
4.6.4 samba - freshly complied from official stable releases on debian:jessie

# Source Code
Check the following link for a new version: https://download.samba.org/pub/samba/stable/

## Environment variables and defaults

### Samba

* __ACCOUNT\_username__
    * multiple variables/accounts possible
    * adds a new user account with the given username and the env value as password

to restrict access of volumes you can add the following to your samba volume config:

    valid users = alice; invalid users = bob;

* __SAMBA\_CONF\_WORKGROUP__
    * default: _WORKGROUP_

* __SAMBA\_CONF\_SERVER\_STRING__
    * default: _file server_

* __SAMBA\_CONF\_MAP_TO_GUEST__
    * default: _Bad User_

* __SAMBA\_CONF\_ENABLE\_PASSWORD\_SYNC__
    * default not set - if set password sync is enabled

* __SAMBA\_VOLUME\_CONFIG\_myconfigname__
    * adds a new samba volume configuration
    * multiple variables/confgurations possible by adding unique configname to SAMBA_VOLUME_CONFIG_
    * examples
        * "[My Share]; path=/shares/myshare; guest ok = no; read only = no; browseable = yes"
        * "[Guest Share]; path=/shares/guests; guest ok = yes; read only = no; browseable = yes"

# Links
* https://wiki.samba.org/index.php/Samba_AD_DC_Port_Usage
* https://wiki.samba.org/index.php/Setting_up_Samba_as_a_Standalone_Server
* https://www.samba.org/samba/docs/man/manpages-3/smb.conf.5.html


# Avahi / Zeroconf

## Infos:

* https://linux.die.net/man/5/avahi.service

You can't proxy the zeroconf inside the container to the outside, since this would need routing and forwarding to your internal docker0 interface from outside.

You can just expose the needed ports to the docker hosts port and install avahi.
After that just add a new service which fits to your config.

### Example Configuration

__/etc/avahi/services/smb.service__

    <?xml version="1.0" standalone='no'?>
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
     <name replace-wildcards="yes">%h</name>
     <service>
       <type>_smb._tcp</type>
       <port>445</port>
     </service>
     <service>
       <type>_device-info._tcp</type>
       <port>0</port>
       <txt-record>model=RackMac</txt-record>
     </service>
    </service-group>
