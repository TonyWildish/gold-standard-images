#!/bin/bash

mirrors=mirrors.eu.txt
if [ ! -f $mirrors ]; then
  wget -O - https://www.centos.org/download/full-mirrorlist.csv \
    | egrep 'France|Germany|Ireland|Switzerland|United Kingdom' \
    | awk -F, '{ print $5 }' \
    | tr -d '"' \
    | tee $mirrors >/dev/null
fi

len=`wc -l $mirrors | cut -f1 -d\ `
rnd=`expr $RANDOM % $len + 1`
mirror=`cat $mirrors| head -$rnd | tail -1`
echo $mirror
