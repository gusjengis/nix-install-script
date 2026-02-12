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

rm -rf "$HOME_MANAGER_DIR"
mkdir -p "$HOME_MANAGER_DIR"
curl -fsSL https://github.com/gusjengis/.home-manager/archive/refs/heads/main.tar.gz | tar -xzf - --strip-components=1 -C "$HOME_MANAGER_DIR"

sudo rm -rf "$NIX_MODULES_DIR"
sudo mkdir -p "$NIX_MODULES_DIR"
curl -fsSL https://github.com/gusjengis/nix-modules/archive/refs/heads/main.tar.gz | sudo tar -xzf - --strip-components=1 -C "$NIX_MODULES_DIR"
sudo chown -R "$TARGET_USER:$TARGET_GROUP" "$NIX_MODULES_DIR"
sudo chown -R "$TARGET_USER:$TARGET_GROUP" "/home/$TARGET_USER"

sudo env NIX_CONFIG="experimental-features = nix-command flakes" nixos-rebuild switch --impure --flake /etc/nix-modules/nixosModules/flake.nix
sudo -u "$TARGET_USER" env NIX_CONFIG="experimental-features = nix-command flakes" home-manager switch --impure --flake "$HOME_MANAGER_DIR/"
