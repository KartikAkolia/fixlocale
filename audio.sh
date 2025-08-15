#!/bin/bash
# Enhanced PipeWire + PulseAudio compatibility setup for Arch Linux
# Features: installation, ALSA blacklisting, state reset, and comprehensive validation
# Usage:
#   ./setup-audio.sh                     # install + enable PipeWire stack
#   ./setup-audio.sh blacklist snd_hda_intel snd_usb_audio
#   ./setup-audio.sh reset               # clears PA/WirePlumber state and restarts
#   ./setup-audio.sh status              # show current audio system status
#   ./setup-audio.sh remove-blacklist    # remove ALSA module blacklist

set -euo pipefail

# Configuration
readonly BLACKLIST_FILE="/etc/modprobe.d/alsa-blacklist.conf"
readonly BACKUP_DIR="$HOME/.config/audio-backup-$(date +%Y%m%d-%H%M%S)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        print_error "It will use sudo when needed for system operations"
        exit 1
    fi
}

# Function to check if on Arch Linux
check_arch() {
    if ! command -v pacman >/dev/null 2>&1; then
        print_error "This script is designed for Arch Linux (pacman not found)"
        exit 1
    fi
}

# Function to check sudo access
check_sudo() {
    if ! sudo -n true 2>/dev/null && ! sudo -v; then
        print_error "This script requires sudo access for system operations"
        exit 1
    fi
}

# Function to create backup of audio configuration
create_audio_backup() {
    print_status "Creating backup of current audio configuration..."
    mkdir -p "$BACKUP_DIR"
    
    # Backup PulseAudio config
    [[ -d "$HOME/.config/pulse" ]] && cp -r "$HOME/.config/pulse" "$BACKUP_DIR/" 2>/dev/null || true
    [[ -d "$HOME/.pulse" ]] && cp -r "$HOME/.pulse" "$BACKUP_DIR/" 2>/dev/null || true
    
    # Backup WirePlumber config
    [[ -d "$HOME/.config/wireplumber" ]] && cp -r "$HOME/.config/wireplumber" "$BACKUP_DIR/" 2>/dev/null || true
    [[ -d "$HOME/.local/state/wireplumber" ]] && cp -r "$HOME/.local/state/wireplumber" "$BACKUP_DIR/wireplumber-state" 2>/dev/null || true
    [[ -d "$HOME/.cache/wireplumber" ]] && cp -r "$HOME/.cache/wireplumber" "$BACKUP_DIR/wireplumber-cache" 2>/dev/null || true
    
    # Backup ALSA config
    [[ -f "$HOME/.asoundrc" ]] && cp "$HOME/.asoundrc" "$BACKUP_DIR/" 2>/dev/null || true
    [[ -f "/etc/asound.conf" ]] && sudo cp "/etc/asound.conf" "$BACKUP_DIR/" 2>/dev/null || true
    
    # Backup blacklist file
    [[ -f "$BLACKLIST_FILE" ]] && sudo cp "$BLACKLIST_FILE" "$BACKUP_DIR/" 2>/dev/null || true
    
    # Save current audio status
    {
        echo "=== Audio System Status Before Changes ==="
        echo "Date: $(date)"
        echo
        echo "=== PulseAudio Info ==="
        pactl info 2>/dev/null || echo "PulseAudio not available"
        echo
        echo "=== Audio Devices ==="
        pactl list short sinks 2>/dev/null || echo "No sinks found"
        pactl list short sources 2>/dev/null || echo "No sources found"
        echo
        echo "=== System Services ==="
        systemctl --user status pipewire pipewire-pulse wireplumber 2>/dev/null || echo "Services not found"
        echo
        echo "=== ALSA Cards ==="
        cat /proc/asound/cards 2>/dev/null || echo "No ALSA cards"
        echo
        echo "=== ALSA Modules ==="
        cat /proc/asound/modules 2>/dev/null || echo "No ALSA modules"
    } > "$BACKUP_DIR/audio-status.txt"
    
    sudo chown -R "$(whoami):$(id -gn)" "$BACKUP_DIR" 2>/dev/null || true
    print_success "Backup created at: $BACKUP_DIR"
}

# Function to show current audio status
show_audio_status() {
    print_status "Current Audio System Status"
    echo "=========================================="
    
    echo
    print_status "PipeWire/PulseAudio Status:"
    if pactl info >/dev/null 2>&1; then
        pactl info | head -15
    else
        print_warning "PulseAudio/PipeWire not responding"
    fi
    
    echo
    print_status "User Services Status:"
    for service in pipewire pipewire-pulse wireplumber; do
        if systemctl --user is-active "$service" >/dev/null 2>&1; then
            status=$(systemctl --user is-active "$service")
            print_success "$service: $status"
        else
            status=$(systemctl --user is-active "$service" 2>/dev/null || echo "inactive")
            print_warning "$service: $status"
        fi
    done
    
    echo
    print_status "Audio Devices:"
    echo "Sinks (output devices):"
    pactl list short sinks 2>/dev/null | sed 's/^/  /' || print_warning "No sinks found"
    echo "Sources (input devices):"
    pactl list short sources 2>/dev/null | sed 's/^/  /' || print_warning "No sources found"
    
    echo
    print_status "ALSA Information:"
    echo "Sound cards:"
    if [[ -f /proc/asound/cards ]]; then
        cat /proc/asound/cards | sed 's/^/  /'
    else
        print_warning "No ALSA cards found"
    fi
    
    echo "Loaded modules:"
    if [[ -f /proc/asound/modules ]]; then
        cat /proc/asound/modules | sed 's/^/  /'
    else
        print_warning "No ALSA modules loaded"
    fi
    
    echo
    if [[ -f "$BLACKLIST_FILE" ]]; then
        print_status "Current ALSA blacklist:"
        sudo cat "$BLACKLIST_FILE" | sed 's/^/  /'
    else
        print_status "No ALSA modules blacklisted"
    fi
    
    echo "=========================================="
}

# Function to install PipeWire stack
install_stack() {
    print_status "Installing PipeWire audio stack..."
    
    # Create backup before making changes
    create_audio_backup
    
    print_status "[1/6] Checking for conflicting packages..."
    local conflicting_packages=(
        "pulseaudio" 
        "pulseaudio-alsa" 
        "pulseaudio-bluetooth"
        "pulseaudio-equalizer"
        "pulseaudio-jack"
        "pulseaudio-lirc"
        "pulseaudio-zeroconf"
    )
    
    local installed_conflicts=()
    for pkg in "${conflicting_packages[@]}"; do
        if pacman -Qi "$pkg" >/dev/null 2>&1; then
            installed_conflicts+=("$pkg")
        fi
    done
    
    if [[ ${#installed_conflicts[@]} -gt 0 ]]; then
        print_warning "Found conflicting packages: ${installed_conflicts[*]}"
        read -p "Remove these packages? [y/N]: " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Removing legacy PulseAudio packages..."
            sudo pacman -Rns --noconfirm "${installed_conflicts[@]}" || {
                print_error "Failed to remove conflicting packages"
                exit 1
            }
            print_success "Conflicting packages removed"
        else
            print_error "Cannot proceed with conflicting packages installed"
            exit 1
        fi
    else
        print_success "No conflicting packages found"
    fi
    
    print_status "[2/6] Installing PipeWire packages..."
    local pipewire_packages=(
        "pipewire"
        "pipewire-pulse" 
        "pipewire-alsa"
        "pipewire-jack"
        "wireplumber"
        "alsa-utils"
        "pavucontrol"
    )
    
    if sudo pacman -S --needed --noconfirm "${pipewire_packages[@]}"; then
        print_success "PipeWire packages installed"
    else
        print_error "Failed to install PipeWire packages"
        exit 1
    fi
    
    print_status "[3/6] Stopping any running audio services..."
    systemctl --user stop pulseaudio.service pulseaudio.socket 2>/dev/null || true
    systemctl --user stop pipewire pipewire-pulse wireplumber 2>/dev/null || true
    
    print_status "[4/6] Enabling PipeWire user services..."
    if systemctl --user enable pipewire.service pipewire-pulse.service wireplumber.service; then
        print_success "Services enabled"
    else
        print_error "Failed to enable services"
        exit 1
    fi
    
    print_status "[5/6] Starting PipeWire services..."
    if systemctl --user start pipewire.service; then
        sleep 1
        if systemctl --user start pipewire-pulse.service; then
            sleep 1
            if systemctl --user start wireplumber.service; then
                print_success "All services started"
            else
                print_error "Failed to start WirePlumber"
                exit 1
            fi
        else
            print_error "Failed to start PipeWire-Pulse"
            exit 1
        fi
    else
        print_error "Failed to start PipeWire"
        exit 1
    fi
    
    print_status "[6/6] Verifying installation..."
    sleep 2
    
    # Check if PipeWire is responding
    local max_attempts=5
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if pactl info >/dev/null 2>&1; then
            break
        fi
        print_status "Waiting for PipeWire to initialize (attempt $attempt/$max_attempts)..."
        sleep 2
        ((attempt++))
    done
    
    if pactl info >/dev/null 2>&1; then
        print_success "PipeWire is running successfully!"
        echo
        print_status "Audio server information:"
        pactl info | head -12
        echo
        print_status "Available audio devices:"
        pactl list short sinks 2>/dev/null || print_warning "No output devices found"
        pactl list short sources 2>/dev/null || print_warning "No input devices found"
    else
        print_error "PipeWire installation may have issues - not responding to pactl"
        exit 1
    fi
    
    print_success "PipeWire installation completed!"
    print_status "Backup created at: $BACKUP_DIR"
}

# Function to blacklist ALSA modules
do_blacklist() {
    shift || true  # Remove 'blacklist' from arguments
    
    if [[ $# -eq 0 ]]; then
        print_error "No modules specified for blacklisting"
        echo "Usage: $0 blacklist <module1> [module2] [...]"
        echo "Example: $0 blacklist snd_hda_intel snd_usb_audio"
        echo
        print_status "Currently loaded ALSA modules:"
        if [[ -f /proc/asound/modules ]]; then
            cat /proc/asound/modules
        else
            print_warning "No ALSA modules currently loaded"
        fi
        exit 2
    fi
    
    check_sudo
    
    print_status "Blacklisting ALSA modules: $*"
    
    # Backup existing blacklist file
    if [[ -f "$BLACKLIST_FILE" ]]; then
        sudo cp "$BLACKLIST_FILE" "${BLACKLIST_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
        print_status "Backed up existing blacklist file"
    fi
    
    # Create blacklist configuration
    {
        echo "# ALSA module blacklist - created $(date)"
        echo "# This file prevents specified ALSA kernel modules from loading"
        echo "#"
        for module in "$@"; do
            echo "blacklist $module"
        done
    } | sudo tee "$BLACKLIST_FILE" >/dev/null
    
    print_success "Created $BLACKLIST_FILE with blacklisted modules: $*"
    
    echo
    print_status "Current system information:"
    echo "Loaded ALSA modules:"
    if [[ -f /proc/asound/modules ]]; then
        cat /proc/asound/modules | sed 's/^/  /'
    else
        print_warning "No ALSA modules currently loaded"
    fi
    
    echo "Sound cards:"
    if [[ -f /proc/asound/cards ]]; then
        cat /proc/asound/cards | sed 's/^/  /'
    else
        print_warning "No sound cards found"
    fi
    
    echo
    print_warning "Blacklist will take effect after reboot"
    print_status "To apply immediately, you can also run: sudo modprobe -r <module_name>"
    print_status "To remove blacklist later, run: $0 remove-blacklist"
}

# Function to remove ALSA blacklist
remove_blacklist() {
    check_sudo
    
    if [[ -f "$BLACKLIST_FILE" ]]; then
        print_status "Removing ALSA module blacklist..."
        sudo rm "$BLACKLIST_FILE"
        print_success "Blacklist file removed"
        print_status "Reboot to allow all ALSA modules to load normally"
    else
        print_status "No blacklist file found at $BLACKLIST_FILE"
    fi
}

# Function to reset PipeWire/WirePlumber state
reset_stack() {
    print_status "Resetting PipeWire/WirePlumber state..."
    
    # Create backup before reset
    create_audio_backup
    
    print_status "[1/4] Stopping user audio services..."
    local services=("wireplumber" "pipewire-pulse" "pipewire" "pulseaudio")
    for service in "${services[@]}"; do
        if systemctl --user is-active "$service" >/dev/null 2>&1; then
            systemctl --user stop "$service" || print_warning "Failed to stop $service"
        fi
    done
    
    # Wait for services to fully stop
    sleep 2
    
    print_status "[2/4] Clearing configuration and cache directories..."
    local dirs_to_clear=(
        "$HOME/.config/pulse"
        "$HOME/.pulse" 
        "$HOME/.local/state/wireplumber"
        "$HOME/.cache/wireplumber"
        "$HOME/.config/wireplumber"  # Optional user config
    )
    
    for dir in "${dirs_to_clear[@]}"; do
        if [[ -d "$dir" ]]; then
            print_status "Removing: $dir"
            rm -rf "$dir"
        fi
    done
    
    # Clear any socket files
    rm -f "$HOME/.pulse/native" "$HOME/.pulse/pid" 2>/dev/null || true
    
    print_success "Configuration and cache cleared"
    
    print_status "[3/4] Starting audio services..."
    if systemctl --user start pipewire.service; then
        sleep 1
        systemctl --user start pipewire-pulse.service || print_warning "Failed to start pipewire-pulse"
        sleep 1
        systemctl --user start wireplumber.service || print_warning "Failed to start wireplumber"
    else
        print_error "Failed to start PipeWire - checking if installed..."
        if ! systemctl --user list-unit-files | grep -q "pipewire.service"; then
            print_error "PipeWire not installed. Run: $0 install"
            exit 1
        fi
    fi
    
    print_status "[4/4] Waiting for services to initialize..."
    sleep 3
    
    # Verify services are running
    local all_good=true
    for service in pipewire pipewire-pulse wireplumber; do
        if systemctl --user is-active "$service" >/dev/null 2>&1; then
            print_success "$service is running"
        else
            print_error "$service failed to start"
            all_good=false
        fi
    done
    
    if [[ "$all_good" == true ]]; then
        print_success "All services restarted successfully"
        
        # Test PipeWire functionality
        if pactl info >/dev/null 2>&1; then
            print_success "PipeWire is responding to commands"
            echo
            print_status "Current audio server info:"
            pactl info | head -12
        else
            print_warning "PipeWire started but not responding to pactl commands"
        fi
    else
        print_error "Some services failed to start - check logs with:"
        echo "  journalctl --user -u pipewire -u pipewire-pulse -u wireplumber"
    fi
    
    print_success "Reset completed!"
    print_status "Backup created at: $BACKUP_DIR" 
    print_status "If issues persist, try logging out and back in"
}

# Function to show usage
show_usage() {
    cat <<EOF
Enhanced PipeWire Audio Setup Script for Arch Linux

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    install                     Install and configure PipeWire stack (default)
    blacklist <modules...>      Blacklist specified ALSA kernel modules
    remove-blacklist           Remove ALSA module blacklist
    reset                      Reset PipeWire/WirePlumber configuration
    status                     Show current audio system status
    help                       Show this help message

EXAMPLES:
    $0                         # Install PipeWire with all components
    $0 install                 # Same as above
    $0 status                  # Show current audio configuration
    $0 blacklist snd_hda_intel snd_usb_audio
    $0 reset                   # Clear all config and restart services
    $0 remove-blacklist        # Remove module blacklist

NOTES:
    • This script creates automatic backups before making changes
    • Blacklisted modules require a reboot to take effect
    • Use 'status' command to diagnose audio issues
    • All operations create timestamped backups in ~/.config/

EOF
}

# Main function
main() {
    local command="${1:-install}"
    
    case "$command" in
        install|"")
            check_root
            check_arch
            check_sudo
            install_stack
            ;;
        blacklist)
            check_arch
            do_blacklist "$@"
            ;;
        remove-blacklist)
            check_arch
            remove_blacklist
            ;;
        reset)
            check_root
            reset_stack
            ;;
        status)
            show_audio_status
            ;;
        help|-h|--help)
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            echo
            show_usage
            exit 2
            ;;
    esac
}

# Run main function with all arguments
main "$@"
