<?php
$url = (isset($_SERVER['HTTPS']) ? "https" : "http") . "://$_SERVER[HTTP_HOST]$_SERVER[REQUEST_URI]";
$first_nameserver = explode(',', $nameserver)[0];
echo "# Boot options:\n";
echo "# inst.ks=$url selinux=0 bootdev=$device ip=$ipaddr gateway=$gateway netmask=$netmask nameserver=$first_nameserver\n";
?>
