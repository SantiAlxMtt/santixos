#!/usr/bin/env bash
# Script de instalación automatizada
# ========
# SANTIXOS
# ========

set -euo pipefail

# Colores para los mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[*] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
error_exit() { echo -e "${RED}[X] $1${NC}"; exit 1; }

# ==========================================
# 1. RECOLECCIÓN DE DATOS (Interactivo)
# ==========================================
clear
echo -e "${CYAN}==============================================${NC}"
echo -e "${CYAN}   INSTALADOR AUTOMÁTICO DE SANTIXOS    ${NC}"
echo -e "${CYAN}==============================================${NC}"
echo ""

# Mostrar discos disponibles para ayudar al usuario
lsblk -d -n -o NAME,SIZE,MODEL | awk '{print "/dev/"$1" - "$2" - "$3}'
echo ""

read -p "1. Ingresa la ruta del disco a formatear (ej. /dev/nvme0n1 o /dev/sda): " DISK
read -p "2. Ingresa el nombre para el equipo (Hostname, ej. mi-laptop): " HOSTNAME
read -p "3. Ingresa tu nombre de usuario (ej. santix): " USERNAME

# --- CONTRASEÑA ROOT ---
while true; do
    read -s -p "4. Ingresa la contraseña para ROOT: " ROOT_PASS
    echo
    read -s -p "   Confirma la contraseña para ROOT: " ROOT_CONFIRM
    echo
    if [ "$ROOT_PASS" == "$ROOT_CONFIRM" ]; then
        break
    else
        warn "Las contraseñas de ROOT no coinciden. Intenta de nuevo."
    fi
done

echo -e "${CYAN}----------------------------------------------${NC}"

# --- CONTRASEÑA USUARIO ---
while true; do
    read -s -p "5. Ingresa la contraseña para el usuario $USERNAME: " USER_PASS
    echo
    read -s -p "   Confirma la contraseña para $USERNAME: " USER_CONFIRM
    echo
    if [ "$USER_PASS" == "$USER_CONFIRM" ]; then
        break
    else
        warn "Las contraseñas de $USERNAME no coinciden. Intenta de nuevo."
    fi
done
echo -e "${CYAN}==============================================${NC}"

# Validar que no se dejaron campos vacíos
if [ -z "$DISK" ] || [ -z "$HOSTNAME" ] || [ -z "$USERNAME" ] || [ -z "$ROOT_PASS" ] || [ -z "$USER_PASS" ]; then
    error_exit "¡Error! No puedes dejar ningún campo en blanco."
fi

# Validar que el disco exista
if [ ! -b "$DISK" ]; then
    error_exit "El disco $DISK no existe. Revisa el nombre."
fi

# Detectar el tipo de partición (NVMe usa 'p1', SATA usan '1')
if [[ "$DISK" == *"nvme"* ]]; then
    PART_EFI="${DISK}p1"
    PART_ROOT="${DISK}p2"
else
    PART_EFI="${DISK}1"
    PART_ROOT="${DISK}2"
fi

warn "¡ADVERTENCIA! Se borrará TODO el contenido de $DISK en 5 segundos."
warn "Presiona Ctrl+C AHORA si quieres cancelar."
sleep 5

# ==========================================
# 2. PREPARACIÓN DEL SISTEMA
# ==========================================
log "Verificando conexion y sincronizando reloj del sistema..."
ping -c 3 archlinux.org
timedatectl set-ntp true
sleep 3

log "Destrucción de particiones y borrado a bajo nivel..."
sgdisk -Z "$DISK"
# Intentamos borrado profundo si es NVMe, si falla, continúa normal
if [[ "$DISK" == *"nvme"* ]]; then
    nvme format "$DISK" --namespace-id=1 --ses=1 || true
fi

log "Particionando el disco ($DISK)..."
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:0:0 -t 2:8304 -c 2:"ROOT" "$DISK"

log "Formateando particiones..."
mkfs.ext4 -F "$PART_ROOT"
mkfs.fat -F32 "$PART_EFI"

log "Montando estructura de archivos..."
mount "$PART_ROOT" /mnt
mount --mkdir "$PART_EFI" /mnt/boot

log "Instalando sistema base con pacstrap..."
pacstrap -K /mnt base base-devel linux-firmware-intel linux-firmware-realtek linux-firmware-whence intel-ucode mkinitcpio zram-generator neovim e2fsprogs efibootmgr dosfstools

log "Generando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# ==========================================
# 3. PREPARANDO EL SCRIPT DE CONFIGURACIÓN INTERNA
# ==========================================
log "Preparando entorno chroot..."

cat << 'EOF' > /mnt/root/chroot_setup.sh
#!/usr/bin/env bash
set -euo pipefail

# Recibir variables
ROOT_PASS="$1"
USER_PASS="$2"
USERNAME="$3"
HOSTNAME="$4"
DISK="$5"
PART_ROOT="$6"

log() { echo -e "\e[32m[CHROOT] $1\e[0m"; }

log "Configurando zona horaria y Locales..."
ln -sf /usr/share/zoneinfo/America/Bogota /etc/localtime
hwclock --systohc
sleep 3

sed -i '/^#en_US.UTF-8 UTF-8/c\en_US.UTF-8 UTF-8' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

log "Creando usuarios y contraseñas..."
echo "root:${ROOT_PASS}" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "${USERNAME}:${USER_PASS}" | chpasswd

echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

log "Añadiendo repositorios de CachyOS..."
pacman -Sy --noconfirm curl tar zstd
curl -sL https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz > /dev/null
cd cachyos-repo && bash cachyos-repo.sh
cd .. && rm -rf cachyos-repo cachyos-repo.tar.xz

log "Optimizando pacman..."
sed -i '/^#Color/c\Color\nILoveCandy' /etc/pacman.conf
sed -i '/^#CheckSpace/c\CheckSpace' /etc/pacman.conf
sed -i '/^#VerbosePkgLists/c\VerbosePkgLists' /etc/pacman.conf
sed -i '/^#ParallelDownloads/c\ParallelDownloads = 5' /etc/pacman.conf

log "Actualizando sistema e instalando dependencias..."
pacman -Syu --noconfirm
pacman -S --noconfirm linux-cachyos linux-cachyos-headers
pacman -S --noconfirm mesa vulkan-intel intel-media-driver vulkan-mesa-layers libvpl vpl-gpu-rt
pacman -S --noconfirm networkmanager iwd pipewire pipewire-pulse pipewire-audio pipewire-alsa pipewire-jack alsa-ucm-conf sof-firmware wireplumber rtkit bluez bluez-utils sudo

log "Configurando NetworkManager y Bluetooth..."
mkdir -p /etc/NetworkManager/conf.d
cat << 'NMWIFI' > /etc/NetworkManager/conf.d/wifi_backend.conf
[device]
wifi.backend=iwd
NMWIFI
systemctl enable NetworkManager
systemctl enable bluetooth.service

log "Aplicando soberanía del driver Intel Xe y ZRAM..."
echo "blacklist i915" > /etc/modprobe.d/i915.conf
echo "options xe force_probe=*" > /etc/modprobe.d/xe.conf

cat << 'ZRAM' > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
ZRAM

log "Instalando CachyOS Tweaks..."
pacman -S --noconfirm cachyos-settings ananicy-cpp cachyos-ananicy-rules scx-scheds scx-tools
cat << 'SCX' > /etc/systemd/scx_loader.toml
default_sched = "scx_bpfland"
default_mode = "Auto"
SCX
systemctl enable ananicy-cpp.service
systemctl enable scx_loader.service

log "Configurando mkinitcpio y Bootloader..."
sed -i '/^MODULES=/c\MODULES=(vmd xe ext4)' /etc/mkinitcpio.conf
sed -i '/^HOOKS=/c\HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)' /etc/mkinitcpio.conf
mkinitcpio -P

bootctl install
efibootmgr --create --disk "$DISK" --part 1 --label "SantixOS" --loader '\EFI\systemd\systemd-bootx64.efi'

cat << 'LOADER' > /boot/loader/loader.conf
default santixos.conf
timeout 0
console-mode max
editor no
LOADER

# Buscamos la partición ROOT dinámicamente
ROOT_UUID=$(blkid -s UUID -o value "$PART_ROOT")

cat << BOOTCONF > /boot/loader/entries/santixos.conf
title SantixOS
linux /vmlinuz-linux-cachyos
initrd /intel-ucode.img
initrd /initramfs-linux-cachyos.img
options root=UUID=${ROOT_UUID} rw i915.force_probe=! xe.force_probe=* loglevel=3 rd.udev.log_priority=3 vt.global_cursor_default=0
BOOTCONF

log "Instalando entorno gráfico (Hyprland)..."
pacman -S --noconfirm hyprland xorg-xwayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk qt5-wayland qt6-wayland hyprland-guiutils hyprpolkitagent hyprpaper hypridle hyprlock uwsm libnewt ttf-jetbrains-mono-nerd inter-font noto-fonts-emoji papirus-icon-theme kvantum kvantum-qt5

log "Configuración Chroot completada."
EOF

chmod +x /mnt/root/chroot_setup.sh

# ==========================================
# 4. EJECUCIÓN FINAL
# ==========================================
log "Entrando al sistema instalado para configurar..."
arch-chroot /mnt /root/chroot_setup.sh "$ROOT_PASS" "$USER_PASS" "$USERNAME" "$HOSTNAME" "$DISK" "$PART_ROOT"

log "Limpiando y desmontando..."
rm /mnt/root/chroot_setup.sh
umount -R /mnt

echo -e "${CYAN}==============================================${NC}"
echo -e "${GREEN}¡INSTALACIÓN COMPLETADA EXITOSAMENTE!${NC}"
echo -e "Ya puedes reiniciar el equipo ejecutando: ${YELLOW}systemctl reboot${NC}"
echo -e "Una vez inicies sesión con tu usuario, ejecuta: ${YELLOW}start-hyprland${NC}"
echo -e "${CYAN}==============================================${NC}"
