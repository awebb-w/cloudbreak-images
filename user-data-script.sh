
# let the script fail to cause the image build unsuccessfull
# set -eo pipefail

[[ "$TRACE" ]] && set -x

: ${IMAGES:=sequenceiq/ambari:1.7.0-consul sequenceiq/consul:v0.4.1.ptr}
: ${DEBUG:=1}

debug() {
    [[ "$DEBUG" ]] && echo "-----> $*" 1>&2
}

install_utils() {
  yum -y install unzip curl git wget cloud-init
  curl -o /usr/bin/jq http://stedolan.github.io/jq/download/linux64/jq && chmod +x /usr/bin/jq
}

install_docker() {
  wget http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
  rpm -Uvh epel-release-6*.rpm
  sudo yum-config-manager --enable epel
  yum install -y device-mapper
  yum install -y docker-io
  service docker start
  chkconfig docker on
}

pull_images() {
  set -e
  for i in ${IMAGES}; do
    docker pull ${i}
  done
}

install_scripts() {
  local target=${1:-/usr/local}
  local provider=$(get_provider_from_packer)

  debug target=$target
  debug provider=$provider

  # script are copied by packer's file provisioner section
  cp /tmp/register-ambari.sh ${target}
  cp /tmp/disk_mount_$provider.sh ${target}/disk_mount.sh
  cp /tmp/public_host_script_$provider.sh ${target}/public_host_script.sh

  chmod +x ${target}/*.sh
  ls -l $target/*.sh

  cp ${target}/register-ambari.sh /etc/init.d/register-ambari
  chown root:root /etc/init.d/register-ambari
  chkconfig register-ambari on
}

fix_hostname() {
  # needed for AWS base image that sets centos6 as hostname
  sudo sed -i "/HOSTNAME/d" /etc/sysconfig/network
  sudo sh -c ' echo "HOSTNAME=localhost.localdomain" >> /etc/sysconfig/network'
  sudo sed -i "/centos6/d" /etc/hosts
}

fix_fstab() {
	sed -i "/dev\/xvdb/ d" /etc/fstab
}

get_provider_from_packer() {
    : ${PACKER_BUILDER_TYPE:? required amazon-ebs/googlecompute/openstack}

    if [[ $PACKER_BUILDER_TYPE =~ amazon ]] ; then
        echo ec2
        return
    fi

    if [[ $PACKER_BUILDER_TYPE == "googlecompute" ]]; then
        echo gce
        return
    fi

    if [[ $PACKER_BUILDER_TYPE == "openstack" ]]; then
        echo openstack
        return
    fi

    if [[ $PACKER_BUILDER_TYPE == "azure" ]]; then
        echo azure
        return
    fi

    echo UNKNOWN_PROVIDER
}

check_params() {
    : ${PACKER_BUILDER_TYPE:? required amazon-ebs/googlecompute/openstack }
}

main() {
    check_params
    install_scripts
    install_utils
    install_docker
    pull_images
    fix_hostname
    fix_fstab
    touch /tmp/ready
    sync
}

[[ "$0" == "$BASH_SOURCE" ]] && main "$@"
