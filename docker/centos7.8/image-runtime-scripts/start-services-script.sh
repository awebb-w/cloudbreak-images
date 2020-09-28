#!/bin/bash

###
# CloudBreak uses unbound as a caching name server. Docker bind-mounts
# /etc/resolv.conf file that is why resolvconf package cannot be used
# as it tries to replace it with a symlink. A workaround is to tranform
# resolv.conf into unbound configuration and set unbound as a nameserver.
###
echo 'forward-zone:' >/etc/unbound/conf.d/99-default.conf
echo '  name: "."' >>/etc/unbound/conf.d/99-default.conf
for nameserver in $(awk '/^nameserver/{print $2}' /etc/resolv.conf); do
  echo "  forward-addr: ${nameserver}" >>/etc/unbound/conf.d/99-default.conf
done

echo 'forward-zone:' >>/etc/unbound/conf.d/99-default.conf
echo '  name: "in-addr.arpa."' >>/etc/unbound/conf.d/99-default.conf
for nameserver in $(awk '/^nameserver/{print $2}' /etc/resolv.conf); do
  echo "  forward-addr: ${nameserver}" >>/etc/unbound/conf.d/99-default.conf
done

echo "nameserver 127.0.0.1" >/etc/resolv.conf

#### Generate input for Ambari from container_limits generated dynamically by YARN
echo "using container_limits to create system resource overrides for ambari"
memoryMb=`cat container_limits | grep memory= | awk -F= '{print $2}'`
memoryKb=`expr $memoryMb \* 1024`
cpu=`cat container_limits | grep vcores= | awk -F= '{print $2}'`
mkdir -p /yarn-private/ambari/
cat <<EOF > /yarn-private/ambari/ycloud.json
{
    "processorcount": "$cpu",
    "physicalprocessorcount": "$cpu",
    "memorysize": "$memoryKb",
    "memoryfree": "$memoryKb",
    "memorytotal": "$memoryKb"
}
EOF

## Cloudbreak related setup
if [[ -f "/etc/cloudbreak-config.props" ]]; then
    cp /etc/resolv.conf.ycloud /etc/resolv.conf

    source /etc/cloudbreak-config.props

    mkdir -p /home/${sshUser}/.ssh
    chmod 700 /home/${sshUser}/.ssh
    echo "${sshPubKey}" >> /home/${sshUser}/.ssh/authorized_keys
    chown -R ${sshUser}:${sshUser} /home/${sshUser}

    echo "${userData}" | base64 -d > /usr/bin/cb-init.sh
    chmod +x /usr/bin/cb-init.sh
    /usr/bin/cb-init.sh
fi


ln -s /yarn-private/ambari /etc/resource_overrides
### End of generating input for Ambari ####################

function setup_non_init_ssh_and_syslog() {

    echo "starting logging service.... "
    ## TODO: Nobody around to restart on failures
    /etc/init.d/syslog start
    echo "starting sshd service ... "

    ## TODO: Nobody around to restart on failures
    /etc/init.d/sshd start

    # Wait for 10 seconds for ssh to show up, otherwise die. Do this all the time.
    while : ; do
      found_pid=no;
      for ((i=0;i<10;i++));
      do
          PID=`pidof sshd`;
          if [ x"$PID"x != "xx" ];
          then
              found_pid=yes;
              break;
          else
              sleep 1;
          fi;
      done
      if [ "$found_pid" == "no" ] ; then
        echo "sshd is dead!" 1>&2
        exit 1
      fi
      sleep 1
    done
}

# Centos7 has systemd
systemctl enable sshd
exec -l /usr/lib/systemd/systemd --system