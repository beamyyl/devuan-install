#!/bin/bash
# =============================================================================
# Devuan Install Script — made by beamyyl
# Supports: UEFI or BIOS + SysVinit or OpenRC
# =============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
ask()   { echo -e "${CYAN}[INPUT]${NC} $*"; }

# =============================================================================
# Sanity checks
# =============================================================================
for cmd in debootstrap chroot mountpoint genfstab blkid; do
    command -v "$cmd" &>/dev/null \
        || die "'$cmd' not found. Ensure you are running from a Linux live environment with debootstrap and arch-install-scripts/util-linux installed."
done

# =============================================================================
# Reminders
# =============================================================================
clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            DEVUAN INSTALLER                              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "This script will bootstrap Devuan to /mnt using debootstrap."
info "Your partitions must be formatted and mounted BEFORE continuing."
echo ""
read -rp "  Press ENTER once your partitions are mounted..."
echo ""

mountpoint -q /mnt || die "/mnt is not mounted."
info "Root mount point verified."
echo ""

# =============================================================================
# Boot mode, init system selection
# =============================================================================
info "============================================================"
info " BOOT MODE, INIT SYSTEM, SUITE"
info "============================================================"
echo ""

ask "Boot mode — UEFI or BIOS?"
ask "  1) UEFI  (modern systems, GPT disk)"
ask "  2) BIOS  (legacy / older systems, MBR or GPT disk)"
read -rp "  Choice [1/2]: " BOOT_CHOICE
case "$BOOT_CHOICE" in
    1) BOOT_MODE="uefi" ;;
    2) BOOT_MODE="bios" ;;
    *) die "Invalid choice. Enter 1 or 2." ;;
esac
echo ""

if [ "$BOOT_MODE" = "uefi" ]; then
    mountpoint -q /mnt/boot/efi \
        || die "/mnt/boot/efi is not mounted. Mount your EFI partition and re-run."
    info "UEFI mode selected. EFI mount verified."
else
    info "BIOS mode selected."
    echo ""
    ask "Enter the disk to install GRUB to (e.g. /dev/sda, /dev/vda)."
    ask "Whole disk, NOT a partition."
    read -rp "  Install disk: " GRUB_DISK
    [ -z "$GRUB_DISK" ] && die "Disk cannot be empty."
    [ -b "$GRUB_DISK" ] || die "'$GRUB_DISK' is not a valid block device."
    info "GRUB will be installed to: $GRUB_DISK"
fi
echo ""

ask "Init system?"
ask "  1) SysVinit (default)"
ask "  2) OpenRC"
read -rp "  Choice [1/2]: " INIT_CHOICE
case "$INIT_CHOICE" in
    1) INIT_SYSTEM="sysvinit" ;;
    2) INIT_SYSTEM="openrc"   ;;
    *) die "Invalid choice. Enter 1 or 2." ;;
esac
echo ""

ask "Devuan suite?"
ask "  1) stable"
ask "  2) testing"
read -rp "  Choice [1/2]: " SUITE_CHOICE
case "$SUITE_CHOICE" in
    1) DEVUAN_SUITE="stable"  ;;
    2) DEVUAN_SUITE="testing" ;;
    *) die "Invalid choice. Enter 1 or 2." ;;
esac
echo ""

info "Selected: suite=$DEVUAN_SUITE  boot=$BOOT_MODE  init=$INIT_SYSTEM"
echo ""

# =============================================================================
# System configuration
# =============================================================================
info "============================================================"
info " SYSTEM CONFIGURATION"
info "============================================================"
echo ""

ask "Enter a hostname for your new system."
read -rp "  Hostname: " NEW_HOSTNAME
[ -z "$NEW_HOSTNAME" ] && die "Hostname cannot be empty."
echo ""

info "Configuration summary:"
echo "   Suite     : $DEVUAN_SUITE"
echo "   Boot mode : $BOOT_MODE"
echo "   Init      : $INIT_SYSTEM"
echo "   Hostname  : $NEW_HOSTNAME"
echo ""
read -rp "  Press ENTER to begin bootstrapping..."
echo ""

# =============================================================================
# Base install (Debootstrap)
# =============================================================================
info "============================================================"
info " BASE INSTALL (DEBOOTSTRAP)"
info "============================================================"
echo ""

info "Bootstrapping Devuan $DEVUAN_SUITE..."
debootstrap --arch=amd64 "$DEVUAN_SUITE" /mnt https://deb.devuan.org/merged

# =============================================================================
# fstab
# =============================================================================
info "============================================================"
info " FSTAB"
info "============================================================"

info "Generating /etc/fstab..."
genfstab -U /mnt > /mnt/etc/fstab || die "Failed to generate /etc/fstab."

# =============================================================================
# In-chroot script
# =============================================================================
info "============================================================"
info " WRITING IN-CHROOT SCRIPT"
info "============================================================"

cat > /mnt/root/chroot-install.sh <<CHROOT_EOF
#!/bin/bash
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "\${GREEN}[CHROOT]\${NC}  \$*"; }
warn()  { echo -e "\${YELLOW}[CHROOT]\${NC}  \$*"; }

BOOT_MODE="${BOOT_MODE}"
INIT_SYSTEM="${INIT_SYSTEM}"
DEVUAN_SUITE="${DEVUAN_SUITE}"
NEW_HOSTNAME="${NEW_HOSTNAME}"
GRUB_DISK="${GRUB_DISK}"

# Configure APT sources based on suite type
if [ "\${DEVUAN_SUITE}" = "testing" ]; then
    cat > /etc/apt/sources.list <<EOF
deb https://deb.devuan.org/merged \${DEVUAN_SUITE} main contrib non-free non-free-firmware
EOF
else
    cat > /etc/apt/sources.list <<EOF
deb https://deb.devuan.org/merged \${DEVUAN_SUITE} main contrib non-free non-free-firmware
deb https://deb.devuan.org/merged \${DEVUAN_SUITE}-updates main contrib non-free non-free-firmware
deb https://deb.devuan.org/merged \${DEVUAN_SUITE}-security main contrib non-free non-free-firmware
EOF
fi

export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y devuan-keyring
apt update

# Install kernel, firmware, device manager (eudev), locales, and basic tools
apt install -y linux-image-amd64 firmware-linux-free firmware-sof-signed eudev vim nano network-manager locales tzdata

# Set timezone and locales
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen

echo "\${NEW_HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${NEW_HOSTNAME}.localdomain \${NEW_HOSTNAME}
EOF

# ---------------------------------------------------------------------------
# Init-specific adjustments
# ---------------------------------------------------------------------------
if [ "\${INIT_SYSTEM}" = "openrc" ]; then
    info "Configuring OpenRC..."
    apt install -y openrc sysvinit-core-
else
    info "Configuring SysVinit..."
    apt install -y sysvinit-core
fi

# ---------------------------------------------------------------------------
# GRUB
# ---------------------------------------------------------------------------
info "Installing GRUB..."

if [ "\${BOOT_MODE}" = "uefi" ]; then
    apt install -y grub-efi-amd64 efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=devuan --recheck
else
    apt install -y grub-pc
    grub-install --recheck "\${GRUB_DISK}"
fi

update-grub

# ---------------------------------------------------------------------------
# Root password
# ---------------------------------------------------------------------------
echo ""
info "============================================================"
info " Set the ROOT password:"
info "============================================================"
passwd

# ---------------------------------------------------------------------------
# Optional new user
# ---------------------------------------------------------------------------
echo ""
echo -e "\${CYAN}[INPUT]\${NC} Would you like to create a new user? (y/n)"
read -rp "  Choice: " CREATE_USER

if [ "\${CREATE_USER}" = "y" ]; then
    echo -e "\${CYAN}[INPUT]\${NC} Enter the new username:"
    read -rp "  Username: " NEW_USER
    if [ -z "\${NEW_USER}" ]; then
        warn "No username entered — skipping user creation."
    else
        useradd -m -G sudo,audio,video,input -s /bin/bash "\${NEW_USER}"
        info "User '\${NEW_USER}' created and added to: sudo, audio, video, input"
        info "Set a password for '\${NEW_USER}':"
        passwd "\${NEW_USER}"
        info "User setup complete."
    fi
else
    info "Skipping user creation."
fi

info "Installation complete!"
CHROOT_EOF

chmod +x /mnt/root/chroot-install.sh
info "In-chroot script written."
echo ""

# =============================================================================
# Bind mounts & Chroot execution
# =============================================================================
info "============================================================"
info " ENTERING CHROOT"
info "============================================================"
echo ""

mount -t proc /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /dev /mnt/dev
mount -t tmpfs tmpfs /mnt/run

chroot /mnt /bin/bash /root/chroot-install.sh

# =============================================================================
# Cleanup
# =============================================================================
info "============================================================"
info " CLEANUP"
info "============================================================"

rm -f /mnt/root/chroot-install.sh

info "Unmounting filesystems..."
umount /mnt/proc /mnt/sys /mnt/dev /mnt/run 2>/dev/null || true
if [ "$BOOT_MODE" = "uefi" ]; then
    umount /mnt/boot/efi 2>/dev/null || true
fi
umount -R /mnt 2>/dev/null || true

echo ""
info "============================================================"
info " All done! Remove your installation media and reboot."
info "============================================================"
