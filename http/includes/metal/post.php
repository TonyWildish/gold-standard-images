# Authorize root access with public ssh key
mkdir -p /root/.ssh
# TODO <?php echo "curl -o /root/.ssh/authorized_keys http://$build_server/ansible/files/xxxxx.pub\n"; ?>
chmod -R u+rwX,go-rwx /root/.ssh

# Disable Nouveau driver
echo "blacklist nouveau" > /etc/modprobe.d/blacklist-nouveau.conf
echo "options nouveau modeset=0" >> /etc/modprobe.d/blacklist-nouveau.conf
