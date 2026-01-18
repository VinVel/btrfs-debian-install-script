#!/bin/bash

# --- Preperation of the Disk and the DE---
lsblk -p

echo "Choose the correct disk, type in this format (example): /dev/nvme0n0"
read DISKInput
export DISK="$DISKInput"

echo "All operations going forward will be executed on this disk: $DISK"

echo "Which Desktop Environment do you want to use? For Gnome, KDE or XFCE? (G, K, X):"
read DE
if [ "$DE" == "G" ]; then
	export DisplayManager="gdm3"
elif [ "$DE" == "K" ]; then
	export DisplayManager="sddm"
elif [ "$DE" == "X" ]; then
	export DisplayManager="lightdm"
fi
echo "Your Debian System will be set up with the following Display Manager: $DisplayManager"
sleep 5


# --- Wipe Disk and Create GPT Partitions ---
apt update && apt upgrade && apt install gdisk -y

# Wipe the disk and create a fresh GPT layout
sgdisk -Z $DISK
sgdisk -og $DISK

# Create EFI system partition (1 GiB)
sgdisk -n 1::+1G -t 1:ef00 -c 1:'ESP' $DISK

# Create root partition (rest of the disk)
sgdisk -n 2:: -t 2:8300 -c 2:'LINUX' $DISK

# Format the EFI partition with FAT32 filesystem
mkfs.fat -F32 -n EFI ${DISK}p1

# Format the main partition with Btrfs filesystem
mkfs.btrfs -L DEBIAN ${DISK}p2

# Verify the filesystem formats
lsblk -po name,size,fstype,fsver,label,uuid $DISK
sleep 5


# --- Create Essential Btrfs Subvolumes ---

# Mount the Btrfs root
mount -v ${DISK}p2 /mnt

# Create essential subvolumes
btrfs subvolume create /mnt/@           			# Root filesystem
btrfs subvolume create /mnt/@home       			# User home data
btrfs subvolume create /mnt/@opt        			# Optional software
btrfs subvolume create /mnt/@cache      			# Cache data
btrfs subvolume create /mnt/@$DisplayManager       	# Display manager data (GNOME)
btrfs subvolume create /mnt/@libvirt    			# Virtual machines
btrfs subvolume create /mnt/@log        			# Log files
btrfs subvolume create /mnt/@spool      			# Spool data
btrfs subvolume create /mnt/@tmp       				# Temporary files
btrfs subvolume create /mnt/@swap       			# Swap file location

# Unmount when done
umount -v /mnt
sleep 5


# --- Mount the Subvolumes for Installation ---

# Define mount options for optimal Btrfs performance
BTRFS_OPTS="defaults,noatime,space_cache=v2,compress=zstd:1"

# Mount the root subvolume
mount -vo $BTRFS_OPTS,subvol=@ ${DISK}p2 /mnt

# Create directories for other subvolumes
mkdir -vp /mnt/home
mkdir -vp /mnt/opt
mkdir -vp /mnt/boot/efi
mkdir -vp /mnt/var/{cache,log,spool,tmp,swap}
mkdir -vp /mnt/var/lib/libvirt
mkdir -vp "/mnt/var/lib/$DisplayManager"


# Mount the remaining subvolumes
mount -vo $BTRFS_OPTS,subvol=@home ${DISK}p2 /mnt/home
mount -vo $BTRFS_OPTS,subvol=@opt ${DISK}p2 /mnt/opt
mount -vo $BTRFS_OPTS,subvol=@cache ${DISK}p2 /mnt/var/cache
mount -vo $BTRFS_OPTS,subvol=@$DisplayManager ${DISK}p2 /mnt/var/lib/$DisplayManager
mount -vo $BTRFS_OPTS,subvol=@libvirt ${DISK}p2 /mnt/var/lib/libvirt
mount -vo $BTRFS_OPTS,subvol=@log ${DISK}p2 /mnt/var/log
mount -vo $BTRFS_OPTS,subvol=@spool ${DISK}p2 /mnt/var/spool
mount -vo $BTRFS_OPTS,subvol=@tmp ${DISK}p2 /mnt/var/tmp

# Mount swap subvolume without compression or CoW for reliability
mount -vo defaults,noatime,subvol=@swap ${DISK}p2 /mnt/var/swap

# Mount the EFI partition
mount -v ${DISK}p1 /mnt/boot/efi

# Verify the mounts
lsblk -po name,size,fstype,uuid,mountpoints $DISK
sleep 5

# --- Install the Debian 13 Base System with debootstrap ---

# Install debootstrap if not already installed
apt install -y debootstrap

# Install base Debian 13 (Trixie) system into /mnt
debootstrap --arch=amd64 trixie /mnt http://deb.debian.org/debian

# Mount necessary filesystems for chroot environment
for dir in dev proc sys run; do
    mount -v --rbind "/${dir}" "/mnt/${dir}"
    mount -v --make-rslave "/mnt/${dir}"
done

# Mount EFI variables (for UEFI systems)
mount -v -t efivarfs efivarfs /mnt/sys/firmware/efi/efivars
sleep 5

# --- Configure fstab ---

# Get UUIDs for Btrfs and EFI partitions
BTRFS_UUID=$(blkid -s UUID -o value ${DISK}p2) ; echo $BTRFS_UUID
EFI_UUID=$(blkid -s UUID -o value ${DISK}p1) ; echo $EFI_UUID

# Create /etc/fstab inside the target system
cat > /mnt/etc/fstab << EOF
UUID=$BTRFS_UUID /                btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@ 0 0
UUID=$BTRFS_UUID /home            btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@home 0 0
UUID=$BTRFS_UUID /opt             btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@opt 0 0
UUID=$BTRFS_UUID /var/cache       btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@cache 0 0
UUID=$BTRFS_UUID /var/lib/$DisplayManager    btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@$DisplayManager 0 0
UUID=$BTRFS_UUID /var/lib/libvirt btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@libvirt 0 0
UUID=$BTRFS_UUID /var/log         btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@log 0 0
UUID=$BTRFS_UUID /var/spool       btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@spool 0 0
UUID=$BTRFS_UUID /var/tmp         btrfs defaults,noatime,space_cache=v2,compress=zstd:1,subvol=@tmp 0 0
UUID=$BTRFS_UUID /var/swap        btrfs defaults,noatime,subvol=@swap 0 0
UUID=$EFI_UUID   /boot/efi        vfat  defaults,noatime 0 2
EOF

# Verify the fstab file content
cat /mnt/etc/fstab
sleep 5

cat > /mnt/root/chroot.sh << 'CHROOT_EOF'
#!/bin/bash

# --- Configure Base System Settings ---
# Set the system hostname
echo "Debian" > /etc/hostname

# Configure /etc/hosts
cat > /etc/hosts << HOSTS_EOF
127.0.0.1       localhost
127.0.1.1       $(cat /etc/hostname)

::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
HOSTS_EOF

# Set the timezone
echo "Set your timezone, e.g. America/New York"
read timezone
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime

# Install and configure locales
apt install -y locales
dpkg-reconfigure locales
sleep 5


# --- Configure Repositories and Install Base Packages ---

# Configure APT sources for Debian 13 (Trixie)
cat > /etc/apt/sources.list << APT_EOF
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
APT_EOF

# Update package lists
apt update && apt upgrade -y

# Install kernel, system tools, and essential utilities
apt install -y linux-image-amd64 linux-headers-amd64 \
    firmware-linux firmware-linux-nonfree \
    grub-efi-amd64 efibootmgr network-manager \
    btrfs-progs sudo vim bash-completion
sleep 5

# --- Create Swap with Hibernation Support ---

# Prepare swap file
truncate -s 0 /var/swap/swapfile
chattr +C /var/swap/swapfile                     # Disable COW
btrfs property set /var/swap compression none    # Disable compression

# My system has 4 GB RAM, so I create 6 GB swap for hibernation (1.5× of RAM)
dd if=/dev/zero of=/var/swap/swapfile bs=1M count=6144 status=progress
chmod 600 /var/swap/swapfile
mkswap -L SWAP /var/swap/swapfile

# Add swap to fstab and enable it
echo "/var/swap/swapfile none swap defaults 0 0" >> /etc/fstab
swapon /var/swap/swapfile
swapon -v

# Configure GRUB for hibernation
SWAP_OFFSET=$(btrfs inspect-internal map-swapfile -r /var/swap/swapfile)
BTRFS_UUID=$(blkid -s UUID -o value ${DISK}p2)
GRUB_CMD="quiet resume=UUID=$BTRFS_UUID resume_offset=$SWAP_OFFSET"
echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMD\"" >> /etc/default/grub

# Update GRUB configuration with new kernel parameters
update-grub

# Configure initramfs for hibernation (using swap file)
cat > /etc/initramfs-tools/conf.d/resume << RESUME_EOF
RESUME=/var/swap/swapfile
RESUME_OFFSET=$SWAP_OFFSET
RESUME_EOF

# Update initramfs to include hibernation support  
update-initramfs -u -k all
sleep 5

# --- Create a User ---

# Create a new user 
echo "Write your username"
read username
echo "Write your Full Name"
read fullName
useradd -m -G sudo,adm -s /bin/bash -c "$fullName" $username

# Set the user password
echo "Set the password for your user: $username"
passwd $username

# Verify the user creation
id $username
sleep 5


# --- Install and Configure GRUB Bootloader ---

# Install GRUB for UEFI
grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id=debian \
  --recheck

# Generate GRUB configuration
update-grub
sleep 5


# --- Exit Chroot---

exit

CHROOT_EOF

chmod +x /mnt/root/chroot.sh
echo "Will now chroot into the Installed system to complete the manual installation"
sleep 3

# --- Chroot into the Installed System ---
chroot /mnt /bin/bash /root/chroot.sh


# --- Reboot --- 

# Unmount all mounted directories
umount -vR /mnt

# Reboot into the installed system
echo "Rebooting in 5 seconds"
sleep 5
reboot