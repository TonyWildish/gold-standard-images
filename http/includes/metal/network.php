<?php
echo "network " . ($device != "" ? "--device $device " : "") . "--bootproto static --ip $ipaddr --hostname $fqdn --netmask $netmask --gateway $gateway --nameserver $nameserver\n";
?>
