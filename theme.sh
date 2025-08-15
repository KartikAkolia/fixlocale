#!/bin/bash
# Enhanced Nordic GTK theme installer with better error handling and features
# Supports GTK2/GTK3/GTK4 and includes backup/restore functionality

set -euo pipefail

# Configuration
readonly THEME_NAME="Nordic"
readonly THEME_VERSION="v2.2.0"
readonly THEME_URL="https://github.com/EliverLara/Nordic/releases/download/${THEME_VERSION}/Nordic.tar.xz"
readonly THEMES_DIR="/usr/share/themes"
readonly BACKUP_DIR="$HOME/.config/gtk-theme-backup-$(date +%Y%m%d-%H%M%S)"

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in curl tar sudo; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_error "Please install them first. On Arch: sudo pacman -S ${missing_deps[*]}"
        exit 1
    fi
}

# Function to create backup of current settings
backup_current_settings() {
    print_status "Creating backup of current GTK settings..."
    mkdir -p "$BACKUP_DIR"
    
    # Backup existing config files if they exist
    [[ -f "$HOME/.config/gtk-3.0/settings.ini" ]] && cp "$HOME/.config/gtk-3.0/settings.ini" "$BACKUP_DIR/gtk-3.0-settings.ini"
    [[ -f "$HOME/.config/gtk-4.0/settings.ini" ]] && cp "$HOME/.config/gtk-4.0/settings.ini" "$BACKUP_DIR/gtk-4.0-settings.ini"
    [[ -f "$HOME/.gtkrc-2.0" ]] && cp "$HOME/.gtkrc-2.0" "$BACKUP_DIR/gtkrc-2.0"
    
    print_success "Backup created at: $BACKUP_DIR"
}

# Function to verify theme installation
verify_theme_installation() {
    if [[ -d "$THEMES_DIR/$THEME_NAME" ]]; then
        print_success "Theme directory verified at $THEMES_DIR/$THEME_NAME"
        
        # Check for essential theme files
        local required_files=("gtk-3.0" "index.theme")
        for file in "${required_files[@]}"; do
            if [[ ! -e "$THEMES_DIR/$THEME_NAME/$file" ]]; then
                print_warning "Required file/directory missing: $file"
            fi
        done
        return 0
    else
        print_error "Theme installation verification failed"
        return 1
    fi
}

# Function to update GTK settings
update_gtk_settings() {
    print_status "Configuring GTK settings for user: $(whoami)"
    
    # GTK3 configuration
    mkdir -p "$HOME/.config/gtk-3.0"
    cat > "$HOME/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=$THEME_NAME
gtk-application-prefer-dark-theme=true
gtk-cursor-theme-name=Adwaita
gtk-font-name=Inter 10
gtk-icon-theme-name=Papirus-Dark
EOF

    # GTK4 configuration
    mkdir -p "$HOME/.config/gtk-4.0"
    cat > "$HOME/.config/gtk-4.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=$THEME_NAME
gtk-application-prefer-dark-theme=true
EOF

    # GTK2 configuration (legacy support)
    cat > "$HOME/.gtkrc-2.0" <<EOF
gtk-theme-name="$THEME_NAME"
gtk-font-name="Inter 10"
EOF

    print_success "GTK configuration files updated"
}

# Function to refresh GTK theme (attempt to apply without logout)
refresh_gtk_theme() {
    print_status "Attempting to refresh GTK theme for current session..."
    
    # Try to reload GTK3 settings
    if command_exists gsettings; then
        gsettings set org.gnome.desktop.interface gtk-theme "$THEME_NAME" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    fi
    
    # Try to refresh using xsettingsd if available
    if pgrep -x "xsettingsd" > /dev/null; then
        pkill -SIGUSR1 xsettingsd 2>/dev/null || true
    fi
}

# Function to show usage
show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -f, --force         Force installation (overwrite existing theme)
    -n, --no-backup     Skip creating backup of current settings
    -q, --quiet         Suppress non-error output
    --restore-backup    Restore from most recent backup

Examples:
    $0                  # Standard installation
    $0 --force          # Force overwrite existing installation
    $0 --no-backup      # Skip backup creation
    $0 --restore-backup # Restore from backup
EOF
}

# Function to restore from backup
restore_from_backup() {
    local latest_backup
    latest_backup=$(find "$HOME/.config" -maxdepth 1 -name "gtk-theme-backup-*" -type d | sort -r | head -n1)
    
    if [[ -z "$latest_backup" ]]; then
        print_error "No backup found to restore from"
        exit 1
    fi
    
    print_status "Restoring from backup: $latest_backup"
    
    [[ -f "$latest_backup/gtk-3.0-settings.ini" ]] && cp "$latest_backup/gtk-3.0-settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
    [[ -f "$latest_backup/gtk-4.0-settings.ini" ]] && cp "$latest_backup/gtk-4.0-settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
    [[ -f "$latest_backup/gtkrc-2.0" ]] && cp "$latest_backup/gtkrc-2.0" "$HOME/.gtkrc-2.0"
    
    print_success "Settings restored from backup"
    exit 0
}

# Main installation function
main() {
    local force_install=false
    local create_backup=true
    local quiet_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--force)
                force_install=true
                shift
                ;;
            -n|--no-backup)
                create_backup=false
                shift
                ;;
            -q|--quiet)
                quiet_mode=true
                shift
                ;;
            --restore-backup)
                restore_from_backup
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Redirect output if quiet mode
    if [[ "$quiet_mode" == true ]]; then
        exec 1>/dev/null
    fi
    
    print_status "Starting Nordic GTK Theme installation ($THEME_VERSION)"
    
    # Check dependencies
    check_dependencies
    
    # Check if theme already exists
    if [[ -d "$THEMES_DIR/$THEME_NAME" ]] && [[ "$force_install" != true ]]; then
        print_warning "Theme already exists at $THEMES_DIR/$THEME_NAME"
        read -p "Continue with installation? [y/N]: " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled"
            exit 0
        fi
    fi
    
    # Create backup if requested
    if [[ "$create_backup" == true ]]; then
        backup_current_settings
    fi
    
    # Create temporary working directory
    local workdir
    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT
    
    print_status "[1/5] Downloading Nordic theme from GitHub..."
    if ! curl -fsSL "$THEME_URL" -o "$workdir/Nordic.tar.xz"; then
        print_error "Failed to download theme from $THEME_URL"
        exit 1
    fi
    
    print_status "[2/5] Extracting theme archive..."
    if ! tar -xf "$workdir/Nordic.tar.xz" -C "$workdir"; then
        print_error "Failed to extract theme archive"
        exit 1
    fi
    
    # Find extracted theme directory
    local theme_dir
    theme_dir="$(find "$workdir" -maxdepth 1 -mindepth 1 -type d -name "*Nordic*" | head -n1)"
    if [[ -z "$theme_dir" ]]; then
        print_error "Failed to find extracted theme directory"
        exit 1
    fi
    
    print_status "[3/5] Installing theme to system directory..."
    sudo mkdir -p "$THEMES_DIR"
    sudo rm -rf "$THEMES_DIR/$THEME_NAME"
    if ! sudo mv "$theme_dir" "$THEMES_DIR/$THEME_NAME"; then
        print_error "Failed to install theme to $THEMES_DIR"
        exit 1
    fi
    
    # Set proper permissions
    sudo chmod -R 755 "$THEMES_DIR/$THEME_NAME"
    
    print_status "[4/5] Verifying installation..."
    verify_theme_installation
    
    print_status "[5/5] Updating GTK configuration..."
    update_gtk_settings
    
    # Try to refresh theme for current session
    refresh_gtk_theme
    
    print_success "Nordic GTK theme installation completed!"
    print_status "Theme installed to: $THEMES_DIR/$THEME_NAME"
    [[ "$create_backup" == true ]] && print_status "Backup created at: $BACKUP_DIR"
    
    echo
    print_status "To fully apply the theme:"
    echo "  • Log out and back in, or restart your desktop session"
    echo "  • For immediate effect in some apps, restart them"
    echo "  • Use your desktop environment's theme settings if available"
    
    if [[ "$create_backup" == true ]]; then
        echo
        print_status "To restore previous settings:"
        echo "  $0 --restore-backup"
    fi
}

# Run main function with all arguments
main "$@"
