ignoredisk --only-use sda
clearpart --drives sda --all --initlabel
zerombr

<?php
if ($boot) {
  echo "part /boot --fstype ext3 --size $bootsize --ondisk sda\n";
}

if ($lvm) {
  echo "part pv.01 --size 1 --grow --ondisk sda\n";
  echo "volgroup ${hostname}_rootvg pv.01 --pesize 32768\n";
  if ($swap) {
    if ($swapsize == "recommended") {
      echo "logvol swap --fstype swap --name swap --vgname ${hostname}_rootvg --recommended\n";
    } else {
      echo "logvol swap --fstype swap --name swap --vgname ${hostname}_rootvg --size $swapsize\n";
    }
  }
  if ($rootsize == "max") {
    echo "logvol / --fstype $fstype --name rootvol --vgname ${hostname}_rootvg --size 1 --grow\n";
  } else {
    echo "logvol / --fstype $fstype --name rootvol --vgname ${hostname}_rootvg --size 1 --grow --maxsize $rootsize\n";
  }
} else {
  echo "part / --fstype $fstype --size 1 --grow --ondisk sda\n";
}
?>
