#!/bin/bash

# --- Install the Desktop Environment ---

echo "Which Desktop Environment do you want to use? For Gnome, KDE or XFCE? (G, K, X):"
read DE
if [ "$DE" == "G" ]; then
	DesktopEnvironment="task-gnome-desktop"
elif [ "$DE" == "K" ]; then
	DesktopEnvironment="task-kde-desktop"
elif [ "$DE" == "X" ]; then
	DesktopEnvironment="task-xfce-desktop"
else
	echo "Invalid selection. Aborting."
    exit 1
fi

sudo apt install -y "$DesktopEnvironment"

# --- Install and Configure Snapper ---

# Install Snapper and required tools
sudo apt install -y snapper btrfs-assistant inotify-tools git make

# Create Snapper config for root (@) and home (@home) subvolumes
sudo snapper -c root create-config /
sudo snapper -c home create-config /home

# Grant user access and synchronize ACLs
sudo snapper -c root set-config ALLOW_USERS=$USER SYNC_ACL=yes
sudo snapper -c home set-config ALLOW_USERS=$USER SYNC_ACL=yes

# List available Snapper configs
sudo snapper list-configs

# Show current settings for root and home
snapper -c root get-config
snapper -c home get-config

# List snapshots for root and home
snapper ls
snapper -c home ls


# --- Install GRUB-Btrfs ---
cat > ~/grub-btrfs-build.sh << 'GRUB_BTRFS_BUILD_EOF'
#!/bin/bash
set -e
cd /tmp

# Clone the GRUB-Btrfs repository from GitHub
git clone https://github.com/Antynea/grub-btrfs.git
cd grub-btrfs

# Edit the configuration to set kernel parameters for snapshots
sed -i.bkp \
  '/^#GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS=/a \
GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="rd.live.overlay.overlayfs=1"' \
  config

# Install GRUB-Btrfs
sudo make install

# Enable and start the GRUB-Btrfs daemon to update
# GRUB automatically when snapshots are created
sudo systemctl enable --now grub-btrfsd.service
GRUB_BTRFS_BUILD_EOF

chmod +x ~/grub-btrfs-build.sh
~/grub-btrfs-build.sh


# --- Enable Automatic Timeline Snapshots ---
cat > ~/snapshot-checker.sh << SNAPSHOTS_EOF
sudo systemctl status snapper-boot.timer
sudo systemctl status snapper-timeline.timer
sudo systemctl status snapper-cleanup.timer
SNAPSHOTS_EOF
chmod +x ~/snapshot-checker.sh

sudo snapper -c home set-config TIMELINE_CREATE=no

# --- Reboot ---
echo "Rebooting in 5 Seconds"
sudo reboot