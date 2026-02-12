#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${1:-gusjengis}"
TARGET_GROUP="$(id -gn "$TARGET_USER")"

NIXOS_DIR="/etc/nixos"
CONFIG_FILE="$NIXOS_DIR/configuration.nix"
HOME_DIR="/home/$TARGET_USER/"
HOME_MANAGER_DIR="$HOME_DIR/.home-manager"
NIX_MODULES_DIR="/etc/nix-modules"

export NIX_CONFIG="experimental-features = nix-command flakes"

sudo chown -R "$TARGET_USER:$TARGET_GROUP" "$NIXOS_DIR"

echo Overriding system config...
STATE_LINE="$(grep -E '^[[:space:]]*system\.stateVersion[[:space:]]*=' "$CONFIG_FILE" | head -n 1)"

cat > "$CONFIG_FILE" <<EOF
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  $STATE_LINE
}
EOF

sudo rm -rf "$NIX_MODULES_DIR"
sudo mkdir -p "$NIX_MODULES_DIR"
echo Downloading system config...
SYSTEM_TAR="$(mktemp)"
curl --fail --location https://github.com/gusjengis/nix-modules/archive/refs/heads/main.tar.gz -o "$SYSTEM_TAR"
sudo tar -xzf "$SYSTEM_TAR" --strip-components=1 -C "$NIX_MODULES_DIR"
rm -f "$SYSTEM_TAR"

rm -rf "$HOME_MANAGER_DIR"
mkdir -p "$HOME_MANAGER_DIR"
echo Downloading home config...
HOME_TAR="$(mktemp)"
curl --fail --location https://github.com/gusjengis/.home-manager/archive/refs/heads/main.tar.gz -o "$HOME_TAR"
tar -xzf "$HOME_TAR" --strip-components=1 -C "$HOME_MANAGER_DIR"
rm -f "$HOME_TAR"
sudo chown -R "$TARGET_USER:$TARGET_GROUP" "$NIX_MODULES_DIR"
sudo chown -R "$TARGET_USER:$TARGET_GROUP" "/home/$TARGET_USER"

echo Installing system config...
sudo env NIX_CONFIG="experimental-features = nix-command flakes" nixos-rebuild switch --impure --flake /etc/nix-modules/nixosModules/
echo Installing home config...
sudo -u "$TARGET_USER" env NIX_CONFIG="experimental-features = nix-command flakes" home-manager switch --impure --flake "$HOME_MANAGER_DIR/"
