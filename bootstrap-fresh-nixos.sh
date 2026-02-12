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
curl -fL# https://github.com/gusjengis/nix-modules/archive/refs/heads/main.tar.gz | sudo tar -xzf - --strip-components=1 -C "$NIX_MODULES_DIR"

rm -rf "$HOME_MANAGER_DIR"
mkdir -p "$HOME_MANAGER_DIR"
echo Downloading home config...
curl -fL# https://github.com/gusjengis/.home-manager/archive/refs/heads/main.tar.gz | tar -xzf - --strip-components=1 -C "$HOME_MANAGER_DIR"
sudo chown -R "$TARGET_USER:$TARGET_GROUP" "$NIX_MODULES_DIR"
sudo chown -R "$TARGET_USER:$TARGET_GROUP" "/home/$TARGET_USER"

echo Installing system config...
sudo env NIX_CONFIG="experimental-features = nix-command flakes" nixos-rebuild switch --impure --flake /etc/nix-modules/nixosModules/
echo Installing home config...
sudo -u "$TARGET_USER" env NIX_CONFIG="experimental-features = nix-command flakes" home-manager switch --impure --flake "$HOME_MANAGER_DIR/"

CURRENT_GIT_NAME="$(sudo -u "$TARGET_USER" git config --global --get user.name || true)"
CURRENT_GIT_EMAIL="$(sudo -u "$TARGET_USER" git config --global --get user.email || true)"

echo "Git authentication:"
read -rp "Git user.name [$CURRENT_GIT_NAME]: " INPUT_GIT_NAME
read -rp "Git user.email [$CURRENT_GIT_EMAIL]: " INPUT_GIT_EMAIL

GIT_NAME="${INPUT_GIT_NAME:-$CURRENT_GIT_NAME}"
GIT_EMAIL="${INPUT_GIT_EMAIL:-$CURRENT_GIT_EMAIL}"

if [ -n "$GIT_NAME" ]; then
  sudo -u "$TARGET_USER" git config --global user.name "$GIT_NAME"
fi

if [ -n "$GIT_EMAIL" ]; then
  sudo -u "$TARGET_USER" git config --global user.email "$GIT_EMAIL"
fi

sudo -u "$TARGET_USER" gh auth login

sudo -u "$TARGET_USER" "$HOME_MANAGER_DIR/scripts/sync-repos.sh"

sudo env NIX_CONFIG="experimental-features = nix-command flakes" nixos-rebuild switch --impure --flake /etc/nix-modules/nixosModules/
sudo -u "$TARGET_USER" env NIX_CONFIG="experimental-features = nix-command flakes" home-manager switch --impure --flake "$HOME_MANAGER_DIR/"
sudo reboot

