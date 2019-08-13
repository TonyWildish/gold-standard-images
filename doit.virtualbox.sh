#!/bin/bash

packer_log=packer.virtualbox.log
[ -f $packer_log ] && cp /dev/null $packer_log

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

base_url="http://mozart.ee.ic.ac.uk/CentOS"
repo_server="$base_url"
iso_server="$base_url"

vb_version=`VBoxManage -v | awk -Fr '{ print $1 }'`
vbga_iso="VBoxGuestAdditions_${vb_version}.iso"
[ -f $vbga_iso ] || wget -O $vbga_iso https://download.virtualbox.org/virtualbox/${vb_version}/$vbga_iso
headless=false
PACKER_LOG=1 \
packer build --force \
  -var-file=http/builds/packer/site.json \
  -var-file=http/builds/packer/os/$image.json \
  $opts \
  --only=virtualbox \
  -var ks_server=http://$host_ip:$port/ \
  -var headless=$headless \
  -var guest_additions_path=$vbga_iso \
  -var iso_server=$iso_server \
  -var repo_server=$repo_server \
  templates/main.json

  # -var guest_additions_path=/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso \
# echo qemu-img convert -p -O qcow2 source-image-file.vmdk converted-image-file.qcow2
