#!/bin/bash

: ${DEBUG:=1}
: ${DRY_RUN:-1}

set -ex -o pipefail -o errexit

function install_salt_with_pip() {
  echo "Installing salt with version: $SALT_VERSION"
  pip install --upgrade pip
  pip install virtualenv
  # fix pip3 not installing virtualenv for root
  ln -s /usr/local/bin/virtualenv /usr/bin/virtualenv
  mkdir ${SALT_PATH}
  virtualenv ${SALT_PATH}
  source ${SALT_PATH}/bin/activate
  pip install -r /tmp/salt_requirements.txt
}

function install_with_apt() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y apt-transport-https python-pip python-dev build-essential
  install_salt_with_pip
  # apt-mark hold salt zeromq zeromq-devel
  install_python_apt_into_virtualenv
  create_temp_minion_config
  if [ "${OS_TYPE}" == "ubuntu14" ]; then
    install_nvme-cli
  fi
}

function install_python_apt_into_virtualenv() {
  source ${SALT_PATH}/bin/activate
  if ! [ -x "$(command -v git)" ]; then
    echo 'git is not installed.'
    apt install -y git
  fi

  # first install build requirements / dependencies
  if [ "${OS_TYPE}" == "ubuntu18" ] || [ "${OS_TYPE}" == "ubuntu16" ]; then
    sed -i 's/^# deb-src/deb-src/g' /etc/apt/sources.list
    apt-get update
  fi
  apt-get -y build-dep python-apt

  pip install git+https://git.launchpad.net/python-apt@${PYTHON_APT_VERSION}

  deactivate
}

function install_nvme-cli () {
  add-apt-repository -y ppa:sbates
  apt-get update -y
  apt-get install -y nvme-cli
}

function install_with_yum() {
  yum update -y python
  yum install -y yum-utils yum-plugin-versionlock
  yum clean metadata
  enable_epel_repository
  yum groupinstall -y 'Development Tools'
  if [ "${OS_TYPE}" == "redhat6" ] ; then
    cp /tmp/repos/${SALT_REPO_FILE} /etc/yum.repos.d/${SALT_REPO_FILE}
    cp /tmp/repos/saltstack-gpg-key.pub /etc/pki/rpm-gpg/saltstack-gpg-key.pub
    yum install -y zeromq zeromq-devel
  fi
  install_python_pip
  echo "exclude=salt" >> /etc/yum.conf
  install_salt_with_pip
  create_temp_minion_config
}

function enable_epel_repository() {
  if [ "${OS}" == "amazonlinux2" ] || [ "${OS}" == "redhat7" ] ; then
    curl https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -o epel-release-latest-7.noarch.rpm && yum install -y ./epel-release-latest-7.noarch.rpm
  elif [ "${OS}" == "amazonlinux" ] ; then
    yum-config-manager --enable epel
  elif [ "${OS_TYPE}" == "redhat7" ] ; then
    curl https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -o epel-release-latest-7.noarch.rpm && yum install -y ./epel-release-latest-7.noarch.rpm &&
	yum install -y unzip &&
	curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" &&
	unzip awscliv2.zip &&
	sudo ./aws/install
  else
    yum install -y epel-release
  fi
}

function install_python_pip() {
  if [ "${OS_TYPE}" == "amazonlinux" ]; then
    yum install -y python27-devel python27-pip
  elif [ "${OS_TYPE}" == "redhat7" ] || [ "${OS_TYPE}" == "amazonlinux2" ] ; then
    echo "Installing python36 with deps"
	subscription-manager register --username "${RH_USER}" --password "${RH_PW}" --auto-attach &&
	subscription-manager repos --enable=rhel-7-server-rpms &&
	subscription-manager repos --enable=rhel-7-server-optional-rpms &&
	yum install -y https://repo.saltstack.com/py3/redhat/salt-py3-repo-latest.el8.noarch.rpm &&
    yum install -y python36 python36-pip python36-devel python36-setuptools
    make_pip3_default_pip 
  else
    yum install -y python-pip python-devel
  fi
}

function make_pip3_default_pip() {
  FILE=/bin/pip
  if [ -f "$FILE" ]; then
      mv /bin/pip /bin/pip2
  fi
  mv /bin/pip3 /bin/pip
  if [ -f "$FILE" ]; then
      mv /bin/pip3.6 /bin/pip
  fi
}

function install_with_zypper() {
  cp /tmp/repos/sles12sp3/* /etc/zypp/repos.d/
  while [[ $(pgrep -f -c zypper) != 0 ]]; do
    echo "Zypper is running, waiting 5 sec to continue"
    sleep 5
  done
  zypper --gpg-auto-import-keys refresh
  if [[ -n "${SLES_REGISTRATION_CODE}" ]] && ! SUSEConnect -s | grep -q \"Registered\"; then
    echo "SLES_REGISTRATION_CODE="$SLES_REGISTRATION_CODE
    SUSEConnect --regcode $SLES_REGISTRATION_CODE
  fi
  if ! SUSEConnect -s | grep -q \"sle-sdk\"; then
    SUSEConnect -p sle-sdk/12.3/x86_64
  fi
  zypper install -y python-simplejson python-pip zypp-plugin-python gcc gcc-c++ make python-devel
  zypper addlock salt zeromq zeromq-devel
  install_salt_with_pip
  create_temp_minion_config
}

function create_temp_minion_config() {
  echo "requests_lib: True" > /tmp/minion
  echo "backend_requests: True" >> /tmp/minion
}

: ${SALT_INSTALL_OS:=$1}

echo "Installing Salt on ${SALT_INSTALL_OS}"
echo "Network interfaces: $(ifconfig)"
echo "Public address: $(curl -s checkip.amazonaws.com)"

case ${SALT_INSTALL_OS} in
  centos|redhat)
    echo "Install with yum"
    install_with_yum
    ;;
 debian|ubuntu)
   echo "Install with apt"
   install_with_apt
   ;;
  amazon)
    echo "Install for Amazon linux"
    echo "Return code: $?"
    echo "Install with yum"
    install_with_yum
   ;;
  suse)
    echo "Install with zypper"
    install_with_zypper
    ;;
 *)
  echo "Unsupported platform:" $1
  exit 1
  ;;
esac
