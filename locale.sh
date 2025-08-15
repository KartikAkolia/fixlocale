#!/bin/bash
# Switch system to UK locale and fix Thunar collation (Arch/xfce)
set -euo pipefail

# 1) Enable en_GB.UTF-8 in /etc/locale.gen (uncomment or add)
if grep -qE '^[[:space:]]*#?[[:space:]]*en_GB\.UTF-8[[:space:]]+UTF-8' /etc/locale.gen; then
  sudo sed -i 's/^[[:space:]]*#\?[[:space:]]*en_GB\.UTF-8[[:space:]]\+UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
else
  echo "en_GB.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen >/dev/null
fi

# 2) Generate locales
sudo locale-gen

# 3) Set system-wide defaults (no LC_ALL)
sudo tee /etc/locale.conf >/dev/null <<'EOF'
LANG=en_GB.UTF-8
LC_COLLATE=en_GB.UTF-8
EOF

# 4) Ensure login environment matches (update or create /etc/environment)
tmp_env=$(mktemp)
if [ -f /etc/environment ]; then
  # remove existing LANG/LC_COLLATE lines
  sudo awk '!/^(LANG|LC_COLLATE)=/' /etc/environment | sudo tee "$tmp_env" >/dev/null
else
  sudo touch "$tmp_env"
fi
{
  echo "LANG=en_GB.UTF-8"
  echo "LC_COLLATE=en_GB.UTF-8"
} | sudo tee -a "$tmp_env" >/dev/null
sudo mv "$tmp_env" /etc/environment

# 5) Restart Thunar daemon for this user (session restart still recommended)
thunar -q >/dev/null 2>&1 || true

echo "Locale set to en_GB.UTF-8 and LC_COLLATE updated."
echo "Log out and back in for all apps (including Thunar) to use the new locale."
