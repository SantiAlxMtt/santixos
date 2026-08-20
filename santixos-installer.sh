#!/usr/bin/env bash
# ==============================================================================
# SANTIXOS - Script de Instalación Automatizada 1.0.0
# Arquitectura: x86_64 | Bash 5.0+ | UI: gum & terminaltexteffects
# ==============================================================================

# Modo Estricto: 
# -e: Aborta si un comando falla.
# -u: Falla si se usa una variable no inicializada.
# -o pipefail: Captura fallos dentro de tuberías (pipes).
set -euo pipefail

# ------------------------------------------------------------------------------
# 1. IDENTIDAD VISUAL (CYBERPUNK) & VARIABLES DE ENTORNO
# ------------------------------------------------------------------------------
export GUM_INPUT_CURSOR_FOREGROUND="#00FFFF"
export GUM_INPUT_PROMPT_FOREGROUND="#FF00FF"
export GUM_CHOOSE_CURSOR_FOREGROUND="#00FF00"
export GUM_CHOOSE_ITEM_FOREGROUND="#FFFFFF"
export GUM_CHOOSE_SELECTED_FOREGROUND="#00FFFF"
export GUM_CONFIRM_SELECTED_BACKGROUND="#FF00FF"
export GUM_CONFIRM_SELECTED_FOREGROUND="#000000"
export GUM_SPIN_SPINNER="dot"
export GUM_SPIN_SPINNER_FOREGROUND="#00FFFF"

readonly INSTALL_LOG="/tmp/santixos_install.log"
readonly BOLD='\033[1m'
readonly RED='\033[1;31m'
readonly DIM='\033[2m'
readonly GREEN='\033[1;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[1;36m'
readonly RESET='\033[0m'

# Estado Global del Instalador (Inicialización explícita)
declare -g target_disk=""
declare -g part_efi=""
declare -g part_root=""
declare -g sys_hostname=""
declare -g sys_username=""
declare -g sys_root_pass=""
declare -g sys_user_pass=""
declare -g animacion_mostrada=0

# ------------------------------------------------------------------------------
# 2. SISTEMA DE LOGGING ESTRUCTURADO (Migrado a printf)
# ------------------------------------------------------------------------------
log_info()  { printf "${CYAN}[ INFO ]${RESET} %s\n" "$1" | tee -a "${INSTALL_LOG}"; }
log_ok()    { printf "${GREEN}[  OK  ]${RESET} %s\n" "$1" | tee -a "${INSTALL_LOG}"; }
log_warn()  { printf "${YELLOW}[ WARN ]${RESET} %s\n" "$1" | tee -a "${INSTALL_LOG}"; }
log_error() { printf "${RED}[ ERROR ]${RESET} %s\n" "$1" | tee -a "${INSTALL_LOG}" >&2; }
error_exit() { log_error "$1"; cleanup_on_exit 1; }

# ------------------------------------------------------------------------------
# 3. VERIFICACIONES DE ENTORNO Y PRIVILEGIOS
# ------------------------------------------------------------------------------
bootstrap_live_usb() {
    # Verificamos dependencias críticas. Si fallan, asumimos Live USB e instalamos en RAM.
    if ! command -v gum >/dev/null 2>&1 || ! command -v tte >/dev/null 2>&1; then
        printf "\n${CYAN}[ INFO ]${RESET} Desplegando dependencias de interfaz en RAM...\n"
        
        local priv=""
        [[ "${EUID}" -ne 0 ]] && priv="sudo"
        
        # Uso de --break-system-packages: Asumimos riesgo calculado en entorno Live USB de Arch
        ${priv} pacman -Sy --needed --noconfirm gum python python-pip >/dev/null 2>&1
        ${priv} pip install terminaltexteffects --break-system-packages >/dev/null 2>&1
        clear
    fi
}

check_dependencies() {
    bootstrap_live_usb	
    local deps=("gum" "tte" "lsblk" "awk")
    local cmd
    
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error_exit "Dependencia crítica ausente en PATH: ${cmd}"
        fi
    done
}

# ------------------------------------------------------------------------------
# 4. GESTIÓN DE SEÑALES (TRAPS) Y LIMPIEZA
# ------------------------------------------------------------------------------
trap 'cleanup_on_exit $?' SIGINT SIGTERM ERR

cleanup_on_exit() {
    local exit_code="${1:-0}"
    # Restaura la visibilidad del cursor si un comando de TUI falló
    tput cvvis 2>/dev/null || true
    
    if [[ "${exit_code}" -ne 0 ]]; then
        log_error "Secuencia interrumpida. Abortando despliegue de forma segura (Código: ${exit_code})."
    fi
    exit "${exit_code}"
}

# ------------------------------------------------------------------------------
# 5. COMPONENTES DE TUI
# ------------------------------------------------------------------------------
print_banner() {
    clear
    local logo="
  ██████╗  █████╗ ███╗   ██╗████████╗██╗██╗  ██╗ ██████╗ ███████╗
 ██╔════╝ ██╔══██╗████╗  ██║╚══██╔══╝██║╚██╗██╔╝██╔═══██╗██╔════╝
 ███████╗ ███████║██╔██╗ ██║   ██║   ██║ ╚███╔╝ ██║   ██║███████╗
 ╚════██║ ██╔══██║██║╚██╗██║   ██║   ██║ ██╔██╗ ██║   ██║╚════██║
 ███████║ ██║  ██║██║ ╚████║   ██║   ██║██╔╝ ██╗╚██████╔╝███████║
 ╚══════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
 ════════════════════════════════════════════════════════════════
                        Instalador v1.0.0                  "   
                  
    if [[ "${animacion_mostrada}" -eq 0 ]]; then
        # Efecto glitch a 60fps con los colores de la identidad
        echo "${logo}" | tte blackhole
        animacion_mostrada=1
    else
        printf "${CYAN}%s${RESET}\n\n" "${logo}"
    fi
}

# ------------------------------------------------------------------------------
# 6. MÓDULOS DEL SISTEMA: MANIFIESTO, RETO E INFORMACIÓN CRÍTICA
# ------------------------------------------------------------------------------

show_info() {
    local readonly max_width=75

    gum style \
        --foreground "#00FFFF" \
        --border "double" \
        --border-foreground "#FF00FF" \
        --padding "1 2" \
        --margin "1 1" \
        --align "center" \
        --width "$max_width" \
        "S A N T I X O S   |   E L   R E T O   Y   E L   M A N I F I E S T O"

    printf "%b%b[ INFO ] Arquitectura Base:%b\n" "${BOLD}" "${CYAN}" "${RESET}"
    gum style --foreground "#D0D0D0" --width "$max_width" --margin "0 0 1 2" \
        "Construido sobre Arch Linux puro. Impulsado por el kernel optimizado de CachyOS y renderizado en el compositor Wayland Hyprland. Diseñado para ofrecer una estética inmersiva sin sacrificar rendimiento."

    printf "%b\033[38;2;57;255;20m[ REWARD ] ¿Por qué abandonar tu zona de confort?%b\n" "${BOLD}" "${RESET}"
    gum style --foreground "#D0D0D0" --width "$max_width" --margin "0 0 1 2" \
        "Aunque requiere una curva de aprendizaje media - alta; Abrazar la terminal y los gestores de ventanas de mosaico (TWM) es un reto formidable. Si vienes de Windows o de interfaces visuales básicas, el choque será fuerte. Pero la recompensa es absoluta. SantixOS te entregará:
• Optimización extrema del procesador: rápido, fluido y sin latencia.
• Mayor duración de batería al erradicar los procesos basura en segundo plano.
• Mayor espacio de almacenamiento libre.
• Mayor porcentaje de ram disponible. 
• Control total y absoluto sobre tu máquina. Dominar este sistema te llevará al siguiente nivel."

    printf "%b%b[ WARN ] Compatibilidad de Hardware (LÉELO DETENIDAMENTE):%b\n" "${BOLD}" "${YELLOW}" "${RESET}"
    gum style --foreground "#D0D0D0" --width "$max_width" --margin "0 0 1 2" \
        "Diseñado para revivir y exprimir laptops o PCs de recursos medios y bajos.
$(gum style --foreground "#FF00FF" --bold "REQUISITO EXCLUSIVO:") Procesadores Intel de 12.ª generación en adelante equipados con gráficas integradas (iGPU).
$(gum style --foreground "#FF003C" --bold "ADVERTENCIA CRÍTICA:") Si tienes procesadores AMD, CPUs antiguas, o dependes de gráficas dedicadas (NVIDIA/Radeon), ABSTENTE DE CONTINUAR. El despliegue fallará estrepitosamente."

    gum style \
        --foreground "#FF003C" \
        --border "rounded" \
        --border-foreground "#FF003C" \
        --padding "1 2" \
        --margin "0 0 1 0" \
        --width "$max_width" \
        "$(gum style --bold --foreground "#FF003C" "[ ERROR / PELIGRO ] PUNTO DE NO RETORNO:")
        
DESTRUCCIÓN TOTAL: Esta instalación borrará y formateará TODA la información del disco seleccionado sin piedad ni posibilidad de recuperación. Asegúrate de tener respaldos."

    printf "  ${CYAN}Dudas, soporte o reporte de bugs:${RESET} \033[4m\033[38;2;255;0;255msantiialxmtt@gmail.com${RESET}\n\n"

    # REFACTORIZACIÓN: Condicional de una sola línea ignorando errores (Fail-Safe visual)
    gum confirm "Asumo el reto, cumplo con el hardware requerido y entiendo los riesgos." --affirmative="Volver al Hub" --negative="" || true
}

# ------------------------------------------------------------------------------
# MÓDULO: RECOLECCIÓN DE DATOS Y TOPOLOGÍA
# ------------------------------------------------------------------------------
collect_installation_data() {
    print_banner
    
    # Animación heredando las variables globales de SantixOS
    gum spin --spinner="${GUM_SPIN_SPINNER}" --spinner.foreground="${GUM_SPIN_SPINNER_FOREGROUND}" --title="Escaneando topología de almacenamiento físico..." -- sleep 2
    
    log_info "Analizando buses PCIe y SATA..."
    
    # FAIL-SAFE: En lugar de input manual, forzamos una selección sobre hardware real
    local disk_list
    # Formateamos la salida de lsblk para que gum choose la consuma limpiamente
    disk_list=$(lsblk -d -n -p -o NAME,SIZE,MODEL | awk '{printf "%-15s │ %-7s │ %s\n", $1, $2, $3}')
    
    if [[ -z "${disk_list}" ]]; then
        error_exit "No se detectaron unidades de almacenamiento válidas en el sistema."
    fi

    printf "\n"
    # Interfaz de selección de hardware interactiva
    local disk_selection
    disk_selection=$(echo "${disk_list}" | gum choose --header="❯ SELECCIONA LA UNIDAD DE DESPLIEGUE (Destino de SantixOS):" --height=10)
    
    # Extracción segura de la ruta del dispositivo seleccionado (/dev/...)
    target_disk=$(echo "${disk_selection}" | awk '{print $1}')
    
    if [[ -z "${target_disk}" ]]; then
        log_warn "Secuencia abortada por el usuario."
        return 1
    fi

    # Validación Estricta: Hostname
    sys_hostname=""
    while [[ ! "${sys_hostname}" =~ ^[a-zA-Z0-9-]+$ ]]; do
        printf "\n"
        log_info "El hostname solo puede contener letras, números y guiones (-)."
        sys_hostname=$(gum input --placeholder "Ej: santixos-cyberdeck" --prompt "❯ Hostname de la máquina: " || true)
    done

    # Validación Estricta: Username (Regex estándar de POSIX)
    sys_username=""
    while [[ ! "${sys_username}" =~ ^[a-z_][a-z0-9_-]*$ ]]; do
        printf "\n"
        log_info "El usuario debe empezar en minúscula, sin espacios ni caracteres especiales."
        sys_username=$(gum input --placeholder "Ej: neo" --prompt "❯ Usuario Administrativo: " || true)
    done

    # Validación Estricta: Credenciales con verificación de vacío
    printf "\n"
    gum style --foreground="#00FFFF" --bold "─── PROTOCOLO DE SEGURIDAD: CREDENCIALES ───"
    
    while true; do
        sys_root_pass=$(gum input --password --placeholder "Contraseña para ROOT" --prompt " ROOT: " || true)
        local root_confirm
        root_confirm=$(gum input --password --placeholder "Confirma Contraseña ROOT" --prompt " Confirmar: " || true)
        
        if [[ "${sys_root_pass}" == "${root_confirm}" && -n "${sys_root_pass}" ]]; then
            break
        fi
        log_warn "Error de sincronización. Las contraseñas de ROOT no coinciden o están vacías."
    done

    while true; do
        sys_user_pass=$(gum input --password --placeholder "Contraseña para ${sys_username}" --prompt " ${sys_username}: " || true)
        local user_confirm
        user_confirm=$(gum input --password --placeholder "Confirma Contraseña ${sys_username}" --prompt " Confirmar: " || true)
        
        if [[ "${sys_user_pass}" == "${user_confirm}" && -n "${sys_user_pass}" ]]; then
            break
        fi
        log_warn "Error de sincronización. Las contraseñas para ${sys_username} no coinciden o están vacías."
    done

    # Lógica de nomenclatura de particiones retenida y estabilizada
    part_efi="${target_disk}1"
    part_root="${target_disk}2"
    # Detecta unidades NVMe/MMC/Loop que requieren la 'p' antes del número de partición
    if [[ "${target_disk}" =~ [0-9]$ ]]; then
        part_efi="${target_disk}p1"
        part_root="${target_disk}p2"
    fi

    printf "\n"
    # Feedback visual estructurado
    gum style --border="rounded" --border-foreground="#00FF00" --padding="1 2" \
        "Topología Compilada:" \
        "EFI:  ${part_efi}" \
        "ROOT: ${part_root}"
    
    printf "\n"
    # Advertencia crítica encapsulada en la UI
    gum style --foreground="#FF0000" --bold "¡ALERTA DE DESTRUCCIÓN CRÍTICA!"
    printf "${DIM}Se construirá una nueva tabla de particiones GPT en ${target_disk}.${RESET}\n"
    printf "${DIM}Todos los datos previos serán vaporizados de forma irrecuperable.${RESET}\n\n"
    
    if ! gum confirm "INICIALIZAR SECUENCIA DE FORMATEO"; then
        log_warn "Operación cancelada por el usuario. Regresando al hub principal..."
        sleep 2
        return 1
    fi
    
    log_ok "Autorización nivel 0 concedida. Preparando actuadores de disco..."
}

# ------------------------------------------------------------------------------
# MÓDULO: DESPLIEGUE DEL SISTEMA BASE Y TOPOLOGÍA DE DISCO
# ------------------------------------------------------------------------------
deploy_base_system() {
    clear
    
    # Renderizado de Cabecera TUI
    gum style \
        --foreground="#FF00FF" \
        --border="double" \
        --border-foreground="#00FFFF" \
        --align="center" \
        --width=60 \
        --margin="1 2" \
        "SANTIXOS: FASE 2 - DESPLIEGUE CORE"

    printf "=== SANTIXOS INSTALL LOG ===\n" > "${INSTALL_LOG}"

    log_info "Inicializando subsistemas de red..."
    # Verificación estricta de conectividad
    if ! gum spin --spinner="${GUM_SPIN_SPINNER}" --spinner.foreground="${GUM_SPIN_SPINNER_FOREGROUND}" --title="Resolviendo DNS y latencia..." -- ping -c 1 -W 3 archlinux.org >> "${INSTALL_LOG}" 2>&1; then
        error_exit "Resolución DNS fallida. Verifica la conectividad o los adaptadores de red."
    fi

    gum spin --spinner="${GUM_SPIN_SPINNER}" --spinner.foreground="${GUM_SPIN_SPINNER_FOREGROUND}" --title="Sincronizando reloj NTP..." -- timedatectl set-ntp true >> "${INSTALL_LOG}" 2>&1 || log_warn "Sincronización NTP inestable."

    # Secuencia de limpieza y destrucción
    log_info "Iniciando secuencia de destrucción en ${target_disk}..."
    
    gum spin --spinner="${GUM_SPIN_SPINNER}" --title="Liberando montajes fantasma..." -- umount -R /mnt 2>/dev/null || true
    gum spin --spinner="${GUM_SPIN_SPINNER}" --title="Purgando firmas mágicas (WipeFS)..." -- wipefs -af "${target_disk}" >> "${INSTALL_LOG}" 2>&1 || error_exit "Fallo al purgar firmas en ${target_disk}."
    gum spin --spinner="${GUM_SPIN_SPINNER}" --title="Destruyendo tabla GPT (sgdisk -Z)..." -- sgdisk -Z "${target_disk}" >> "${INSTALL_LOG}" 2>&1 || error_exit "Fallo al destruir tabla de particiones."

    # Secure Erase Condicional para unidades NVMe
    if [[ "${target_disk}" =~ nvme ]] && command -v nvme >/dev/null 2>&1; then
        log_info "Unidad NVMe detectada. Solicitando borrado criptográfico seguro..."
        gum spin --spinner="pulse" --title="Ejecutando Secure Erase NVMe..." -- nvme format "${target_disk}" --namespace-id=1 --ses=1 >> "${INSTALL_LOG}" 2>&1 || log_warn "Secure Erase no soportado por el firmware del disco. Omitiendo."
    fi

    # Particionado
    log_info "Forjando nueva topología de almacenamiento..."
    gum spin --spinner="${GUM_SPIN_SPINNER}" --title="Creando vector EFI (1GB)..." -- sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI" "${target_disk}" >> "${INSTALL_LOG}" 2>&1 || error_exit "Fallo al crear partición EFI."
    gum spin --spinner="${GUM_SPIN_SPINNER}" --title="Asignando bloque ROOT (100%)..." -- sgdisk -n 2:0:0 -t 2:8304 -c 2:"ROOT" "${target_disk}" >> "${INSTALL_LOG}" 2>&1 || error_exit "Fallo al crear partición ROOT."
    
    # Sincronización del kernel con la tabla de particiones
    partprobe "${target_disk}" >> "${INSTALL_LOG}" 2>&1
    sleep 2

    # Formateo con Fail-Safe
    gum spin --spinner="${GUM_SPIN_SPINNER}" --title="Dando formato EXT4 a ${part_root}..." -- mkfs.ext4 -F "${part_root}" >> "${INSTALL_LOG}" 2>&1 || error_exit "Fallo al formatear partición ROOT (${part_root})."
    gum spin --spinner="${GUM_SPIN_SPINNER}" --title="Dando formato FAT32 a ${part_efi}..." -- mkfs.fat -F32 "${part_efi}" >> "${INSTALL_LOG}" 2>&1 || error_exit "Fallo al formatear partición EFI (${part_efi})."

    # Montaje estructural
    mount "${part_root}" /mnt || error_exit "Fallo al montar el sistema de archivos raíz."
    mount --mkdir "${part_efi}" /mnt/boot || error_exit "Fallo al crear/montar la estructura EFI."
    
    log_ok "Estructura de directorios base acoplada con éxito."
    printf "\n"

    # Inyección Pacstrap
    log_info "Iniciando inyección del sistema base (Pacstrap)..."
    printf "${DIM} ❯ Monitoreo en segundo plano: tail -f %s${RESET}\n" "${INSTALL_LOG}"
    
    # Se añade 'linux-zen' como kernel por defecto para preparar el terreno del compositor Wayland y latencia ultra-baja. 
    # Se reemplaza el ucode estático por la variable dinámica calculada.
    local pacstrap_pkgs=(
        base base-devel linux-firmware-intel linux-firmware-realtek linux-firmware-whence intel-ucode 
        "${ucode_pkg}" mkinitcpio zram-generator neovim 
        e2fsprogs efibootmgr dosfstools git networkmanager
    )

    if gum spin --spinner="${GUM_SPIN_SPINNER}" --spinner.foreground="#FF00FF" --title="Construyendo Core OS (Esto puede tardar)..." -- \
        pacstrap -K /mnt "${pacstrap_pkgs[@]}" >> "${INSTALL_LOG}" 2>&1; then
        log_ok "Inyección de paquetes finalizada."
    else
        error_exit "Fallo crítico durante Pacstrap. El sistema base no pudo construirse."
    fi

    # FSTAB Automático
    gum spin --spinner="${GUM_SPIN_SPINNER}" --title="Generando fstab estructural..." -- genfstab -U /mnt >> /mnt/etc/fstab || error_exit "No se pudo generar el archivo fstab."
    
    printf "\n"
    log_ok "Fase 2 completada. Motor central de SantixOS preparado."
}

# ------------------------------------------------------------------------------
# MÓDULO: EJECUCIÓN Y CONFIGURACIÓN CHROOT (FASE 3)
# ------------------------------------------------------------------------------
execute_chroot_configuration() {
    clear
    gum style \
        --foreground="#00FFFF" \
        --border="double" \
        --border-foreground="#FF00FF" \
        --align="center" \
        --width=60 \
        --margin="1 2" \
        "SANTIXOS: FASE 3 - INYECCIÓN CHROOT"

    log_info "Generando plano de ejecución y bóveda de credenciales..."

    # FAIL-SAFE: Garantiza la destrucción de los secretos sin importar cómo termine la función
    trap 'rm -f /mnt/root/.santixos_env /mnt/root/chroot_setup.sh; log_info "Bóveda de credenciales destruida por seguridad."' RETURN ERR INT TERM

    # 1. CREACIÓN DE LA BÓVEDA SEGURA (VAULT)
    cat << ENV_VAULT > /mnt/root/.santixos_env
export CHROOT_ROOT_PASS="${sys_root_pass}"
export CHROOT_USER_PASS="${sys_user_pass}"
export CHROOT_USERNAME="${sys_username}"
export CHROOT_HOSTNAME="${sys_hostname}"
export CHROOT_PART_ROOT="${part_root}"
export CHROOT_DISK="${target_disk}"
ENV_VAULT
    chmod 600 /mnt/root/.santixos_env

    # 2. GENERACIÓN DEL SCRIPT CHROOT
    cat << 'EOF' > /mnt/root/chroot_setup.sh
#!/usr/bin/env bash
# ==============================================================================
# SANTIXOS - Motor de Configuración Interna (Entorno Chroot)
# ==============================================================================
# -e: Falla al primer error
# -u: Falla si hay variables no definidas
# -o pipefail: Falla si un comando en un pipe falla
set -euo pipefail

readonly CHROOT_LOG="/var/log/santixos_chroot.log"
printf "=== SANTIXOS CHROOT LOG ===\n" > "${CHROOT_LOG}"

# Identidad Visual TUI Básica (Sin dependencias externas)
readonly BOLD='\033[1m'
readonly RED='\033[1;31m'
readonly GREEN='\033[1;32m'
readonly YELLOW='\033[1;33m'
readonly MAGENTA='\033[1;35m'
readonly CYAN='\033[1;36m'
readonly RESET='\033[0m'

# Funciones de Logging (Migradas a printf)
log_info()  { printf "${CYAN}[ CHROOT ]${RESET} %s\n" "$1" | tee -a "${CHROOT_LOG}"; }
log_ok()    { printf "${GREEN}[   OK   ]${RESET} %s\n" "$1" | tee -a "${CHROOT_LOG}"; }
log_warn()  { printf "${YELLOW}[  WARN  ]${RESET} %s\n" "$1" | tee -a "${CHROOT_LOG}"; }
log_step()  { printf "\n${BOLD}${MAGENTA} ❯ %s ${RESET}\n" "$1" | tee -a "${CHROOT_LOG}"; }

trap 'printf "\n${RED}[ X ] Error crítico detectado en Chroot. Revisa ${CHROOT_LOG}${RESET}\n"; exit 1' ERR

if [[ -f /root/.santixos_env ]]; then
    source /root/.santixos_env
    # Se elimina la bóveda inmediatamente después de cargarla en RAM
    rm -f /root/.santixos_env
else
    printf "${RED}[ ERROR ]${RESET} Bóveda de credenciales no encontrada. Abortando.\n"
    exit 1
fi

log_step "Forjando Localización y Reloj de Hardware..."
ln -sf /usr/share/zoneinfo/America/Bogota /etc/localtime
hwclock --systohc >> "${CHROOT_LOG}" 2>&1

sed -i '/^#en_US.UTF-8 UTF-8/c\en_US.UTF-8 UTF-8' /etc/locale.gen
locale-gen >> "${CHROOT_LOG}" 2>&1
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "${CHROOT_HOSTNAME}" > /etc/hostname
log_ok "Vector de identidad host (${CHROOT_HOSTNAME}) establecido."

log_step "Compilando perfiles de usuario y anillos de seguridad..."
echo "root:${CHROOT_ROOT_PASS}" | chpasswd
useradd -m -G wheel -s /bin/bash "${CHROOT_USERNAME}"
echo "${CHROOT_USERNAME}:${CHROOT_USER_PASS}" | chpasswd

mkdir -p /etc/sudoers.d
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
log_ok "Credenciales encriptadas y aplicadas."

log_step "Inyectando repositorios de rendimiento extremo (CachyOS)..."
pacman -Sy --noconfirm curl tar zstd >> "${CHROOT_LOG}" 2>&1

curl -fSL "https://mirror.cachyos.org/cachyos-repo.tar.xz" -o /tmp/cachyos-repo.tar.xz
tar xvf /tmp/cachyos-repo.tar.xz -C /tmp >> "${CHROOT_LOG}" 2>&1

# FIX CRÍTICO: Se expone la salida del script CachyOS directamente al usuario 
# para permitir las confirmaciones interactivas obligatorias.
printf "\n${CYAN}>>> ATENCIÓN: El instalador de CachyOS requiere interacción manual.${RESET}\n"
printf "${CYAN}>>> Por favor, confirma (Y) los avisos en pantalla.${RESET}\n\n"

cd /tmp/cachyos-repo
bash cachyos-repo.sh
cd /

rm -rf /tmp/cachyos-repo*

log_info "Reescribiendo pacman.conf (Optimizaciones)..."
sed -i '/^#Color/c\Color\nILoveCandy' /etc/pacman.conf
sed -i '/^#CheckSpace/c\CheckSpace' /etc/pacman.conf
sed -i '/^#VerbosePkgLists/c\VerbosePkgLists' /etc/pacman.conf
sed -i '/^#ParallelDownloads/c\ParallelDownloads = 5' /etc/pacman.conf

log_info "Configurando Initramfs (VMD / Xe Intel)..."
sed -i '/^MODULES=/c\MODULES=(vmd xe ext4)' /etc/mkinitcpio.conf
sed -i '/^HOOKS=/c\HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)' /etc/mkinitcpio.conf

log_step "Sincronizando red troncal e instalando dependencias núcleo..."
pacman -Syu --noconfirm >> "${CHROOT_LOG}" 2>&1
pacman -S --noconfirm linux-cachyos linux-cachyos-headers \
    mesa vulkan-intel intel-media-driver vulkan-mesa-layers libvpl vpl-gpu-rt \
    networkmanager iwd pipewire pipewire-pulse pipewire-audio pipewire-alsa \
    pipewire-jack alsa-ucm-conf sof-firmware wireplumber rtkit bluez bluez-utils sudo >> "${CHROOT_LOG}" 2>&1

log_step "Desplegando hipervisores de red, ZRAM y Schedulers..."
mkdir -p /etc/NetworkManager/conf.d
cat << 'NMWIFI' > /etc/NetworkManager/conf.d/wifi_backend.conf
[device]
wifi.backend=iwd
NMWIFI

systemctl enable NetworkManager.service >> "${CHROOT_LOG}" 2>&1
systemctl enable bluetooth.service >> "${CHROOT_LOG}" 2>&1

log_info "Forzando drivers modernos Intel Xe..."
echo "blacklist i915" > /etc/modprobe.d/i915.conf
echo "options xe force_probe=*" > /etc/modprobe.d/xe.conf

log_info "Inicializando motor ZRAM (zstd)..."
cat << 'ZRAM' > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
ZRAM

log_info "Inyectando CPU Scheduler (SCX / BPF)..."
pacman -S --noconfirm cachyos-settings ananicy-cpp cachyos-ananicy-rules scx-scheds scx-tools >> "${CHROOT_LOG}" 2>&1
cat << 'SCX' > /etc/systemd/scx_loader.toml
default_sched = "scx_bpfland"
default_mode = "Auto"
SCX
systemctl enable ananicy-cpp.service >> "${CHROOT_LOG}" 2>&1
systemctl enable scx_loader.service >> "${CHROOT_LOG}" 2>&1

log_step "Construyendo sector de arranque (systemd-boot)..."
bootctl install >> "${CHROOT_LOG}" 2>&1

cat << 'LOADER' > /boot/loader/loader.conf
default santixos.conf
timeout 0
console-mode max
editor no
LOADER

readonly ROOT_UUID=$(blkid -s UUID -o value "${CHROOT_PART_ROOT}")

cat << BOOTCONF > /boot/loader/entries/santixos.conf
title SantixOS
linux /vmlinuz-linux-cachyos
initrd /intel-ucode.img
initrd /initramfs-linux-cachyos.img
options root=UUID=${ROOT_UUID} rw i915.force_probe=! xe.force_probe=* loglevel=3 rd.udev.log_priority=3 vt.global_cursor_default=0
BOOTCONF

log_step "Inyectando Compositor Tiling (Hyprland / Wayland)..."
pacman -S --noconfirm hyprland xorg-xwayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk qt5-wayland qt6-wayland hyprland-guiutils hyprpolkitagent hyprpaper hypridle hyprlock uwsm libnewt ttf-jetbrains-mono-nerd inter-font noto-fonts-emoji papirus-icon-theme kvantum kvantum-qt5 >> "${CHROOT_LOG}" 2>&1

printf "\n"
log_ok "Operaciones internas (Chroot) finalizadas con éxito."
EOF

    chmod +x /mnt/root/chroot_setup.sh

    log_info "Transfiriendo control a chroot_setup.sh..."
    printf "${DIM} ❯ Este proceso despliega el núcleo visual y del kernel. Requerirá tu confirmación en pantalla.\n${RESET}"
    
    arch-chroot /mnt /root/chroot_setup.sh || error_exit "El script Chroot falló. Revisa /mnt/var/log/santixos_chroot.log"

    # Se desactiva el trap principal ya que el script interno borró los archivos exitosamente
    trap - RETURN ERR INT TERM
    
    gum spin --spinner="${GUM_SPIN_SPINNER}" --title="Validando purga de rastros temporales..." -- rm -f /mnt/root/chroot_setup.sh /mnt/root/.santixos_env
    
    log_ok "Subsistema Chroot desacoplado de manera segura."
}

start_installation() {
    # Orquestador del flujo real
    deploy_base_system
    execute_chroot_configuration
    finalize_installation
}

# ------------------------------------------------------------------------------
# MÓDULO: FINALIZACIÓN Y DESACOPLE (FASE 4)
# ------------------------------------------------------------------------------
finalize_installation() {
    clear
    gum style \
        --foreground="#00FFFF" \
        --border="double" \
        --border-foreground="#FF00FF" \
        --align="center" \
        --width=60 \
        --margin="1 2" \
        "SANTIXOS: FASE FINAL - DESACOPLE"

    # 1. SINCRONIZACIÓN DE HARDWARE (I/O Buffer Sync)
    log_info "Asegurando integridad de datos en hardware persistente..."
    gum spin --spinner="${GUM_SPIN_SPINNER}" --spinner.foreground="${GUM_SPIN_SPINNER_FOREGROUND}" --title="Volcando caché RAM a disco (sync)..." -- sync || log_warn "Aviso menor durante la sincronización I/O."
    sleep 1

    # 2. DESMONTAJE SEGURO
    log_info "Desacoplando estructura de archivos..."
    gum spin --spinner="${GUM_SPIN_SPINNER}" --spinner.foreground="${GUM_SPIN_SPINNER_FOREGROUND}" --title="Desmontando subvolúmenes en /mnt..." -- umount -R /mnt 2>/dev/null || true

    # 3. ANIMACIÓN DE ÉXITO (Cyberpunk TUI)
    clear
    local readonly success_banner="
  ███████╗ █████╗ ███╗   ██╗████████╗██╗██╗  ██╗ ██████╗ ███████╗
  ██╔════╝██╔══██╗████╗  ██║╚══██╔══╝██║╚██╗██╔╝██╔═══██╗██╔════╝
  ███████╗███████║██╔██╗ ██║   ██║   ██║ ╚███╔╝ ██║   ██║███████╗
  ╚════██║██╔══██║██║╚██╗██║   ██║   ██║ ██╔██╗ ██║   ██║╚════██║
  ███████║██║  ██║██║ ╚████║   ██║   ██║██╔╝ ██╗╚██████╔╝███████║
  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝

 ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
                 [ SISTEMA DESPLEGADO CON ÉXITO ]
 ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄"

    # Aplicación del efecto laseretch para impacto visual extremo (60fps)
    printf "%s\n" "${success_banner}" | tte laseretch
    printf "\n"

    # 4. INSTRUCCIONES DE DESPLIEGUE FINAL
    printf " %bVector de Entrada Post-Instalación:%b\n" "${BOLD}" "${RESET}"
    
    # Inyección de variable global estandarizada con fallback de seguridad
    gum style --margin="0 2" --foreground="#00FFFF" "1. Autenticación requerida como: $(gum style --foreground="#FF00FF" --bold "${sys_username:-operador}")"
    gum style --margin="0 2" --foreground="#00FFFF" "2. Ejecuta $(gum style --foreground="#00FF00" --bold "Hyprland") para inicializar el compositor Wayland."
    printf "\n"

    # 5. REINICIO CONTROLADO Y LIMPIEZA DE TERMINAL
    log_info "Secuencia de despliegue finalizada."
    
    # Interacción final para evitar reinicios forzados, cediendo el control al operador
    if gum confirm "Transición completa. ¿Iniciar secuencia de reinicio de hardware?" --affirmative="Reiniciar Ahora" --negative="Salir a Shell"; then
        log_info "Ejecutando señal ACPI de reinicio..."
        
        # Restaurar estados de TTY antes del reinicio
        tput cvvis 2>/dev/null || true
        stty echo 2>/dev/null || true
        
        systemctl reboot
    else
        log_info "Reinicio cancelado. Puedes revisar ${INSTALL_LOG} o reiniciar manualmente con 'reboot'."
        # Restaurar visibilidad del cursor antes de soltar la terminal
        tput cvvis 2>/dev/null || true
        exit 0
    fi
}

# ------------------------------------------------------------------------------
# 6. BUCLE PRINCIPAL (MAIN LOOP)
# ------------------------------------------------------------------------------
main_menu() {
    check_dependencies
    while true; do
        print_banner
        local choice
        choice=$(gum choose "1) Instalar SantixOS" "2) Manifiesto de Arquitectura | (Leer Antes de Instalar)" "3) Salir" || echo "")
        
        case "${choice}" in
            "1) Instalar SantixOS") 
                # REFACTORIZACIÓN CRÍTICA: Enlace del flujo de ejecución.
                # Si la recolección de datos es exitosa, se dispara la instalación.
                if collect_installation_data; then
                    start_installation
                else
                    continue
                fi
                ;;
            "2) Manifiesto de Arquitectura | (Leer Antes de Instalar)") 
                show_info 
                ;;
            "3) Salir") 
                log_info "Desconectando..."
                exit 0 
                ;;
            "") 
                continue 
                ;;
        esac
    done
}
