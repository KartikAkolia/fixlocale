#!/bin/bash
# Switch system to UK locale and fix Thunar collation (Arch/XFCE)
# Improved version with better error handling and validation

set -euo pipefail

readonly TARGET_LOCALE="en_GB.UTF-8"
readonly TARGET_CHARSET="UTF-8"

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

print_info() { echo -e "[INFO] $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Check if running as root (should use sudo instead)
if [[ $EUID -eq 0 ]]; then
    print_error "Don't run as root - script will use sudo when needed"
    exit 1
fi

# Check sudo access
if ! sudo -n true 2>/dev/null && ! sudo -v; then
    print_error "This script requires sudo access"
    exit 1
fi

# Verify we're on an Arch-based system
if [[ ! -f /etc/locale.gen ]]; then
    print_error "/etc/locale.gen not found - this script is for Arch-based systems"
    exit 1
fi

print_info "Setting system locale to ${TARGET_LOCALE}..."

# 1) Enable en_GB.UTF-8 in /etc/locale.gen (uncomment or add)
print_info "[1/5] Configuring /etc/locale.gen..."

# Create backup of locale.gen
sudo cp /etc/locale.gen /etc/locale.gen.backup

if grep -qE "^[[:space:]]*#?[[:space:]]*${TARGET_LOCALE}[[:space:]]+${TARGET_CHARSET}" /etc/locale.gen; then
    # Uncomment existing line
    sudo sed -i "s/^[[:space:]]*#\?[[:space:]]*${TARGET_LOCALE}[[:space:]]\+${TARGET_CHARSET}/${TARGET_LOCALE} ${TARGET_CHARSET}/" /etc/locale.gen
    print_success "Enabled existing ${TARGET_LOCALE} entry"
else
    # Add new entry
    echo "${TARGET_LOCALE} ${TARGET_CHARSET}" | sudo tee -a /etc/locale.gen >/dev/null
    print_success "Added ${TARGET_LOCALE} entry"
fi

# 2) Generate locales
print_info "[2/5] Generating locales..."
if sudo locale-gen; then
    print_success "Locales generated successfully"
else
    print_error "Failed to generate locales"
    exit 1
fi

# Verify locale was generated
if ! locale -a | grep -q "^${TARGET_LOCALE}$"; then
    print_error "Failed to generate ${TARGET_LOCALE} - check /etc/locale.gen"
    exit 1
fi

# 3) Set system-wide defaults (backup existing file first)
print_info "[3/5] Updating /etc/locale.conf..."
[[ -f /etc/locale.conf ]] && sudo cp /etc/locale.conf /etc/locale.conf.backup

sudo tee /etc/locale.conf >/dev/null <<EOF
LANG=${TARGET_LOCALE}
LC_COLLATE=${TARGET_LOCALE}
EOF
print_success "Updated /etc/locale.conf"

# 4) Ensure login environment matches (update or create /etc/environment)
print_info "[4/5] Updating /etc/environment..."

# Backup existing environment file
[[ -f /etc/environment ]] && sudo cp /etc/environment /etc/environment.backup

# Create temporary file with proper permissions
tmp_env=$(mktemp)
trap 'rm -f "$tmp_env"' EXIT

if [[ -f /etc/environment ]]; then
    # Remove existing LANG/LC_COLLATE lines and preserve others
    sudo awk '!/^(LANG|LC_COLLATE)=/' /etc/environment > "$tmp_env" 2>/dev/null || true
fi

# Add our locale settings
{
    echo "LANG=${TARGET_LOCALE}"
    echo "LC_COLLATE=${TARGET_LOCALE}"
} >> "$tmp_env"

# Move to final location with proper permissions
sudo mv "$tmp_env" /etc/environment
sudo chmod 644 /etc/environment
print_success "Updated /etc/environment"

# 5) Update systemd locale if available
print_info "[5/5] Updating system configuration..."
if command -v localectl >/dev/null 2>&1; then
    if sudo localectl set-locale LANG="${TARGET_LOCALE}" LC_COLLATE="${TARGET_LOCALE}"; then
        print_success "Updated systemd locale settings"
    else
        print_warning "Failed to update systemd locale (continuing anyway)"
    fi
else
    print_warning "localectl not available - skipping systemd update"
fi

# Restart Thunar daemon for immediate effect (if running)
if command -v thunar >/dev/null 2>&1; then
    if pgrep -f "thunar" >/dev/null; then
        print_info "Restarting Thunar for immediate effect..."
        thunar -q >/dev/null 2>&1 || true
        sleep 1
        # Restart daemon in background
        thunar --daemon >/dev/null 2>&1 &
        print_success "Thunar restarted"
    fi
fi

# Final verification
print_info "Verifying configuration..."
if grep -q "LANG=${TARGET_LOCALE}" /etc/locale.conf && 
   grep -q "LC_COLLATE=${TARGET_LOCALE}" /etc/locale.conf &&
   locale -a | grep -q "^${TARGET_LOCALE}$"; then
    print_success "All configuration files updated successfully"
else
    print_error "Verification failed - some settings may not be applied"
    exit 1
fi

echo
print_success "UK locale (${TARGET_LOCALE}) configuration completed!"
echo
echo "Changes made:"
echo "  • /etc/locale.gen - enabled ${TARGET_LOCALE}"
echo "  • /etc/locale.conf - set LANG and LC_COLLATE"  
echo "  • /etc/environment - set LANG and LC_COLLATE"
echo "  • systemd locale settings updated"
echo
echo "Backup files created:"
echo "  • /etc/locale.gen.backup"
echo "  • /etc/locale.conf.backup (if existed)"
echo "  • /etc/environment.backup (if existed)"
echo
print_warning "IMPORTANT: Log out and back in for all applications to use the new locale"
print_info "Current locale will be: $(locale 2>/dev/null | grep LANG= || echo "LANG=${TARGET_LOCALE}")"
