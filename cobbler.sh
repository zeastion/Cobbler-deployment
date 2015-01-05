#!/bin/bash

# Values

HOSTNAME=`hostname`
HOSTIP=`ifconfig|grep 'inet addr:'|grep -v '127.0.0.1'|cut -d: -f2|awk '{print $1}'`
echo -e "\n-------------\n| HOST NAME - $HOSTNAME\n-------------"
echo -e "-------------\n| HOST  IP  - $HOSTIP\n-------------"

IPSTART="10.2.30.5"
IPEND="10.2.30.100"

NODEPASS="qwe123"

# Hostname

more /etc/hosts | grep "$HOSTNAME" >/dev/null 2>&1
if [ $? -ne 0 ];then
    echo -e "$HOSTIP\t$HOSTNAME" >> /etc/hosts
fi

# Iptables

lokkit -p 53:tcp
lokkit -p 53:udp
lokkit -p 67:udp
lokkit -p 68:udp
lokkit -p 69:udp
lokkit -p 69:tcp
lokkit -p 80:tcp
lokkit -p 123:udp
lokkit -p 443:tcp
lokkit -p 25150:udp
lokkit -p 25151:tcp
lokkit -p 25152:tcp
lokkit -p 8140:tcp

echo -e "-------------\n| Iptables  -\n-------------"
iptables -S

# SELinux

setenforce 0 >/dev/null 2>&1
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
echo -e "\n-------------\n| SELinux   -\n-------------"
getenforce

# Add yum repo

echo -e "\n-------------\n| Add repo  -\n-------------"

yum install http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm -y >/dev/null 2>&1

if [ $? -ne 0 ] && [ ! -f /etc/yum.repos.d/epel.repo ]; then
    echo -e "\n ***  Add EPEL Repository Failed  ***\n"
    exit
else
    yum repolist
fi

# Install packages

echo -e "\n-------------\n| Packages  -\n-------------\n\n Wait a minute ...\n"

packages="cobbler debmirror pykickstart cman puppet-server ntp dnsmasq"

for pak in $packages
do
    yum info $pak >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "Can't find package \e[0;31;1m$pak\e[0m"
    else
        yum info $pak 2>/dev/null | grep "From repo" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "Package \e[0;31;1m$pak\e[0m has already been installed"
        else
            echo -e "Installing \e[0;31;1m$pak\e[0m ..."
            yum install $pak -y >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo -e "Install package \e[0;31;1m$pak\e[0m successfully"
            else
                echo -e "\n ***  Install Package \e[0;31;1m$pak\e[0m Failed  ***\n"
                exit
            fi
        fi
    fi
done

# Puppet agent snippet

sed -i "/# don/a \echo \"$HOSTIP\t$HOSTNAME\" >> /etc/hosts\necho \"    report = true\" >> /etc/puppet/puppet.conf\necho \"    server = $HOSTNAME\" >> /etc/puppet/puppet.conf\necho \"    pluginsync = true\" >> /etc/puppet/puppet.conf" /var/lib/cobbler/snippets/puppet_register_if_enabled

# Autosign all nodes

echo "*" > /etc/puppet/autosign.conf

# Services

echo -e "\n-------------\n| Services  -\n-------------"

services="httpd cobblerd dnsmasq puppetmaster"

for ser in $services
do
    service $ser restart
    if [ $? -ne 0 ]; then
        echo -e "\n ***  Start \e[0;31;1m$ser\e[0m Failed  ***\n"
        exit
    else
        chkconfig $ser on
    fi
done

# Fix cobbler check

cobbler get-loaders 1>/dev/null

sed -i -e 's/\=\ yes/\=\ no/g' /etc/xinetd.d/rsync
sed -i '/disable/c\\tdisable\t\t\t= no' /etc/xinetd.d/tftp
service xinetd restart

sed -i -e 's|@dists=.*|#@dists=|' /etc/debmirror.conf
sed -i -e 's|@arches=.*|#@arches=|' /etc/debmirror.conf

# Dnsmasq

sed -i "s/^dhcp-range=.*/dhcp-range=$IPSTART,$IPEND/g" /etc/cobbler/dnsmasq.template
sed -i '/^dhcp-option=3,$next_server$/i\dhcp-ignore=#known\nserver=8.8.8.8' /etc/cobbler/dnsmasq.template

sed -i 's/^module = manage_bind$/module = manage_dnsmasq/g' /etc/cobbler/modules.conf 
sed -i 's/^module = manage_isc$/module = manage_dnsmasq/g' /etc/cobbler/modules.conf

# Dynamic settings

sed -i.bak 's/allow_dynamic_settings: 0/allow_dynamic_settings: 1/g' /etc/cobbler/settings
service cobblerd restart >/dev/null 2>&1

echo -e "\n-------------\n| Setting   -\n-------------"

settings1="server next_server"

for sett1 in $settings1
do
    cobbler setting edit --name=$sett1 --value=$HOSTIP #>/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\n ***  Set \e[0;31;1m$sett1\e[0m failed  ***\n"
        exit
    else
        echo -e "Cobbler - \e[0;31;1m$sett1\e[0m has been set"
    fi
done

cobbler setting edit --name=default_password_crypted --value="`openssl passwd -1 -salt "zeastion" "$NODEPASS"`"

if [ $? -ne 0 ]; then
    echo -e "\n ***  Set \e[0;31;1mdefault_password\e[0m failed  ***\n"
    exit
else
    echo -e "Cobbler - \e[0;31;1mdefault_password\e[0m has been set"
fi


settings2="pxe_just_once manage_rsync manage_dhcp manage_dns puppet_auto_setup sign_puppet_certs_automatically remove_old_puppet_certs_automatically"

for sett2 in $settings2
do
    cobbler setting edit --name=$sett2 --value=1 >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\n ***  Set \e[0;31;1m$sett2\e[0m failed  ***\n"
        exit
    else
        echo -e "Cobbler - \e[0;31;1m$sett2\e[0m has been set"
    fi
done

# Sync

service cobblerd restart >/dev/null 2>&1
cobbler sync >/dev/null 2>&1

err=$?
if [ $err -ne 0 ]; then
    echo -e "\n ***  Deploy Cobbler Failed  ***\n"
    exit
fi

# End

echo -e "\n-----------------------------\n| Cobbler has been deployed |\n-----------------------------"
echo -e "| Node Password - $NODEPASS \n-----------------------------"
