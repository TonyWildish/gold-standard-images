<?php
require "includes/header.php";

if (file_exists("includes/$hardware/bootline.php")) {
  include "includes/$hardware/bootline.php";
}
?>

install
cmdline
unsupported_hardware

<?php require "includes/repo.php"; ?>

<?php require "includes/locale.php"; ?>

<?php require "includes/$hardware/network.php"; ?>

<?php require "includes/rootpw.php"; ?>

authconfig --enableshadow --passalgo sha512
firewall --enabled --port 22:tcp
selinux --disabled
firstboot --disabled

bootloader --location mbr --driveorder sda --append "rdblacklist=nouveau nouveau.modeset=0"

<?php require "includes/disk.php"; ?>

reboot

%packages --nobase
@core
man
openssh-clients
system-config-firewall-base
%end

%post
<?php require "includes/$hardware/post.php" ?>
%end
