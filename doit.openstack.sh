#!/bin/bash

export PACKER_LOG_PATH=packer.openstack.log
[ -f $PACKER_LOG_PATH ] && cp /dev/null $PACKER_LOG_PATH

set -ex
ksServer='ks-server'
port=8080
if [ `docker ps | grep $ksServer | wc -l` -eq 0 ]; then
  docker run \
    -it \
    --detach \
    --rm \
    --name $ksServer \
    --volume `pwd`/http:/var/www/html \
    --volume `pwd`/templates:/var/www/templates \
    --publish $port:80 \
    php:7.3.2-apache-stretch
fi

version="7.6.1810"
image="CentOS-${version}"

if [ "$KS_HOST_IP" != "" ]; then
  host_ip=$KS_HOST_IP
else
  # host_ip=`docker inspect -f "{{ .NetworkSettings.IPAddress }}" $ksServer`
  host_ip=`ifconfig | grep 'inet ' | egrep -v 127.0.0.1 | awk '{ print $2 }' | tail -1`
  if [ `wget -O - "http://$host_ip:$port/ks.php?build=virtual/virtualbox&os=$image" | wc -l` -ne 0 ]; then
    echo "Found host IP $host_ip"
  else
    echo "Can't find kickstart host IP. If you're on a Mac, the candidates are:"
    echo `ifconfig | grep 'inet ' | egrep -v 127.0.0.1 | awk '{ print $2 }'`
    exit 0
  fi
fi

# centos_mirror="http://mozart.ee.ic.ac.uk/CentOS"
if [ $RANDOM_MIRROR ]; then
  CENTOS_MIRROR=`./get-centos-uk-mirror.sh`
fi
centos_mirror=${CENTOS_MIRROR:=http://45.86.170.150/CentOS}
repo_server=${REPO_SERVER:=$centos_mirror}
iso_server=http://45.86.170.150/CentOS # "http://mozart.ee.ic.ac.uk/CentOS" #${ISO_SERVER:=$centos_mirror}

template="templates/os/${image}.json.template"
target="http/builds/packer/os/${image}.json"
target2="templates/os/${image}.json"
cat $template \
  | sed -e "s%__REPO_SERVER__%$repo_server%g" \
        -e "s%__ISO_SERVER__%$iso_server%g" \
  | tee $target \
  | tee $target2 \
  > /dev/null

# opts="-on-error=ask -debug"
export ANSIBLE_DEBUG=0
export ANSIBLE_SSH_ARGS="-C -o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
export ANSIBLE_SSH_ARGS="-v $ANSIBLE_SSH_ARGS"
export headless=true
export PACKER_LOG=1
packer build --force \
  -var-file=http/builds/packer/site.json \
  -var-file=http/builds/packer/os/$image.json \
  $opts \
  --only=openstack \
  -var ks_server=http://$host_ip:$port/ \
  -var headless=$headless \
  templates/main.json
