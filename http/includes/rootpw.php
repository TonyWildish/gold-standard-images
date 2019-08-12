<?php
$cryptedpw = crypt("${packer_site['root_pass']}", '$6$rounds=5000$' . "${packer_site['root_salt']}" . '$');
echo "rootpw --iscrypted $cryptedpw\n";
?>
