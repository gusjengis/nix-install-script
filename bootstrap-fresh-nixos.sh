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

if [ "${BOOTSTRAP_IN_NIX_SHELL:-0}" != "1" ]; then
  exec nix --extra-experimental-features "nix-command flakes" shell nixpkgs#git -c env BOOTSTRAP_IN_NIX_SHELL=1 bash "$0" "$@"
fi

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

git -C "$NIXOS_DIR" init
git -C "$NIXOS_DIR" add -A
git -C "$NIXOS_DIR" -c user.name="$TARGET_USER" -c user.email="$TARGET_USER@$(hostname -s)" commit -m "initial /etc/nixos"

git clone https://github.com/gusjengis/.home-manager.git "$HOME_MANAGER_DIR"
sudo git clone https://github.com/gusjengis/nix-modules.git "$NIX_MODULES_DIR"
sudo chown -R "$TARGET_USER:$TARGET_GROUP" "$NIX_MODULES_DIR"
sudo chown -R "$TARGET_USER:$TARGET_GROUP" "/home/$TARGET_USER"

sudo env NIX_CONFIG="experimental-features = nix-command flakes" nixos-rebuild switch --impure --flake /etc/nix-modules/nixosModules/flake.nix
sudo -u "$TARGET_USER" env NIX_CONFIG="experimental-features = nix-command flakes" home-manager switch --impure --flake "$HOME_MANAGER_DIR/"
