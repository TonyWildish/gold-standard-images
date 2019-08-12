<?php
// Common defaults
$hardware = "virtual";           // Hardware type (virtual/metal)
$fstype = "xfs";                 // Filesystem type
$lvm = 1;                        // Use LVM
$boot = 1;                       // Create a boot partition
$bootsize = 1024;                // Size of boot in MiB
$swap = 1;                       // Create a swap partition
$swapsize = "recommended";       // Size of swap in MiB
$rootsize = "max";               // Size of root LV in MiB
?>
