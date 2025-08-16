#!/bin/bash

# Meslo Nerd Font Auto-Installer Script
# This script downloads and installs the Meslo Nerd Font from GitHub

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required programs are installed
check_dependencies() {
    print_status "Checking dependencies..."
    
    local missing_deps=()
    
    for cmd in wget unzip 7z; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required programs: ${missing_deps[*]}"
        print_status "Please install them first:"
        print_status "  Ubuntu/Debian: sudo apt install wget unzip p7zip-full"
        print_status "  Fedora: sudo dnf install wget unzip p7zip"
        print_status "  Arch: sudo pacman -S wget unzip p7zip"
        exit 1
    fi
    
    print_success "All dependencies are installed"
}

# Create fonts directory if it doesn't exist
create_fonts_dir() {
    local fonts_dir="$HOME/.local/share/fonts"
    
    if [ ! -d "$fonts_dir" ]; then
        print_status "Creating fonts directory: $fonts_dir"
        mkdir -p "$fonts_dir"
    else
        print_status "Fonts directory already exists: $fonts_dir"
    fi
}

# Download Meslo font
download_font() {
    local download_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/Meslo.zip"
    local fonts_dir="$HOME/.local/share/fonts"
    
    print_status "Downloading Meslo Nerd Font..."
    
    cd "$fonts_dir"
    
    # Remove existing zip file if it exists
    if [ -f "Meslo.zip" ]; then
        print_warning "Existing Meslo.zip found, removing..."
        rm Meslo.zip
    fi
    
    # Download the font
    if wget -q --show-progress "$download_url"; then
        print_success "Download completed"
    else
        print_error "Failed to download font"
        exit 1
    fi
}

# Check if Meslo fonts are already installed
check_existing_fonts() {
    local fonts_dir="$HOME/.local/share/fonts"
    
    print_status "Checking for existing Meslo fonts..."
    
    # Check if any Meslo font files exist
    if find "$fonts_dir" -name "*Meslo*" -type f 2>/dev/null | grep -q .; then
        print_warning "Meslo fonts already found in $fonts_dir"
        
        # List existing Meslo fonts
        print_status "Existing Meslo fonts:"
        find "$fonts_dir" -name "*Meslo*" -type f 2>/dev/null | sed 's/^/  /'
        
        echo
        read -p "Do you want to reinstall/update? (y/N): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled by user"
            exit 0
        else
            print_status "Removing existing Meslo fonts..."
            find "$fonts_dir" -name "*Meslo*" -type f -delete 2>/dev/null
            print_success "Existing fonts removed"
        fi
    else
        print_status "No existing Meslo fonts found"
    fi
}

# Extract font files
extract_font() {
    local fonts_dir="$HOME/.local/share/fonts"
    
    print_status "Extracting font files..."
    
    cd "$fonts_dir"
    
    if 7z x Meslo.zip -y > /dev/null; then
        print_success "Font files extracted"
    else
        print_error "Failed to extract font files"
        exit 1
    fi
    
    # Clean up zip file
    print_status "Cleaning up..."
    rm Meslo.zip
    print_success "Zip file removed"
}

# Refresh font cache
refresh_font_cache() {
    print_status "Refreshing font cache..."
    
    if fc-cache -fv > /dev/null 2>&1; then
        print_success "Font cache refreshed"
    else
        print_error "Failed to refresh font cache"
        exit 1
    fi
}

# Verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    if fc-list | grep -i "meslo" > /dev/null; then
        print_success "Meslo Nerd Font successfully installed!"
        print_status "Available Meslo fonts:"
        fc-list | grep -i "meslo" | cut -d: -f2 | sort | uniq | sed 's/^/  /'
    else
        print_warning "Font may not be properly installed. Try running 'fc-cache -fv' manually."
    fi
}

# Main function
main() {
    echo "======================================="
    echo "  Meslo Nerd Font Auto-Installer"
    echo "======================================="
    echo
    
    check_dependencies
    create_fonts_dir
    check_existing_fonts
    download_font
    extract_font
    refresh_font_cache
    verify_installation
    
    echo
    print_success "Installation completed successfully!"
    print_status "You can now use Meslo Nerd Font in your terminal and applications."
    print_status "You may need to restart your terminal or applications to see the new font."
}

# Run the main function
main
