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

echo -e "$HOSTIP\t$HOSTNAME" >> /etc/hosts

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
    echo -e "\n ***   YUM 源添加失败  ***\n"
    exit
else
    yum repolist
fi

# Install packages

echo -e "\n-------------\n| Packages  -\n-------------\n\n Wait a minute ...\n"

packages="cobbler debmirror pykickstart cman dnsmasq"

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
                echo -e "\n ***   软件包 \e[0;31;1m$pak\e[0m 安装失败 请检查网络及YUM源  ***\n"
                exit
            fi
        fi
    fi
done

# Services

echo -e "\n-------------\n| Services  -\n-------------"

service cobblerd restart && chkconfig cobblerd on
service dnsmasq restart && chkconfig dnsmasq on

# Fix cobbler check

cobbler get-loaders 1>/dev/null

sed -i -e 's/\=\ yes/\=\ no/g' /etc/xinetd.d/rsync
sed -i '/disable/c\\tdisable\t\t\t= no' /etc/xinetd.d/tftp
service xinetd restart

sed -i -e 's|@dists=.*|#@dists=|' /etc/debmirror.conf
sed -i -e 's|@arches=.*|#@arches=|' /etc/debmirror.conf

# Dnsmasq

sed -i "s/^dhcp-range=.*/dhcp-range=$IPSTART,$IPEND/g" /etc/cobbler/dnsmasq.template
sed -i '/^dhcp-option=3,$next_server$/i\dhcp-ignore=tag:!known\nserver=8.8.8.8' /etc/cobbler/dnsmasq.template

sed -i 's/^module = manage_bind$/module = manage_dnsmasq/g' /etc/cobbler/modules.conf 
sed -i 's/^module = manage_isc$/module = manage_dnsmasq/g' /etc/cobbler/modules.conf

# Dynamic settings

sed -i.bak 's/allow_dynamic_settings: 0/allow_dynamic_settings: 1/g' /etc/cobbler/settings
service cobblerd restart >/dev/null 2>&1

cobbler setting edit --name=server --value=$HOSTIP
cobbler setting edit --name=next_server --value=$HOSTIP
cobbler setting edit --name=pxe_just_once --value=1

cobbler setting edit --name=manage_rsync --value=1
cobbler setting edit --name=manage_dhcp --value=1
cobbler setting edit --name=manage_dns --value=1

cobbler setting edit --name=default_password_crypted --value="`openssl passwd -1 -salt "zeastion" "$NODEPASS"`"

# Sync

service httpd restart && chkconfig httpd on >/dev/null 2>&1
service cobblerd restart && cobbler sync 1>/dev/null # 2>&1

err=$?
if [ $err -ne 0 ]; then
    echo -e "\n ***  Cobbler 部署失败 请检查日志  ***\n"
    exit
fi

# End

echo -e "\n-----------------------------\n| Cobbler has been deployed |\n-----------------------------"
echo -e "| Node Password - $NODEPASS \n-----------------------------"
