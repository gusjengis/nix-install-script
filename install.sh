#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${1:-gusjengis}"
TARGET_GROUP="$(id -gn "$TARGET_USER")"

NIXOS_DIR="/etc/nixos"
CONFIG_FILE="$NIXOS_DIR/configuration.nix"
HOME_DIR="/home/$TARGET_USER"
HOME_MANAGER_DIR="$HOME_DIR/.home-manager"
HOME_MODULES_FILE="$HOME_MANAGER_DIR/modules.nix"
NIX_MODULES_DIR="/etc/nix-modules"
SYSTEM_MODULES_DIR="$NIX_MODULES_DIR/nixosModules"

export NIX_CONFIG="experimental-features = nix-command flakes"

declare -A CURRENT_PICK_DEFAULTS=()
declare -A CURRENT_PICK_PREVIEWS=()

discover_enable_options() {
  local root_dir="$1"
  [[ -d "$root_dir" ]] || return 0

  grep -RhoE '[[:space:]]*(options\.)?[A-Za-z0-9_.-]+\.enable[[:space:]]*=[[:space:]]*lib\.mkEnableOption' "$root_dir" 2>/dev/null \
    | sed -E 's/^[[:space:]]*//; s/[[:space:]]*=.*$//; s/^options\.//' \
    | sed -E 's/\.enable$//' \
    | sort -u
}

discover_source_defaults() {
  local root_dir="$1"
  local defaults_map_name="$2"
  local exclude_modules_file="${3:-false}"
  local file line opt value
  local in_option_block=0
  local current_option=""
  local -n defaults_ref="$defaults_map_name"

  [[ -d "$root_dir" ]] || return 0

  while IFS= read -r -d '' file; do
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_.-]+)\.enable[[:space:]]*=[[:space:]]*lib\.mkDefault[[:space:]]*(true|false)[[:space:]]*\; ]]; then
        opt="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        defaults_ref["$opt"]="$value"
      fi

      if [[ "$line" =~ ^[[:space:]]*options\.([A-Za-z0-9_.-]+)\.enable[[:space:]]*=[[:space:]]*lib\.mkEnableOption ]]; then
        in_option_block=1
        current_option="${BASH_REMATCH[1]}"

        if [[ "$line" =~ default[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*\; ]]; then
          value="${BASH_REMATCH[1]}"
          defaults_ref["$current_option"]="$value"
        fi

        if [[ "$line" == *";" ]]; then
          in_option_block=0
          current_option=""
        fi
        continue
      fi

      if [[ "$in_option_block" -eq 1 ]]; then
        if [[ "$line" =~ default[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*\; ]]; then
          value="${BASH_REMATCH[1]}"
          defaults_ref["$current_option"]="$value"
        fi

        if [[ "$line" == *"};"* || "$line" == *";"* ]]; then
          in_option_block=0
          current_option=""
        fi
      fi
    done < "$file"
  done < <(
    if [[ "$exclude_modules_file" == "true" ]]; then
      find "$root_dir" -type f -name '*.nix' ! -name 'modules.nix' ! -name 'local.nix' -print0
    else
      find "$root_dir" -type f -name '*.nix' -print0
    fi
  )
}

discover_option_previews() {
  local root_dir="$1"
  local previews_map_name="$2"
  local exclude_modules_file="${3:-false}"
  shift 3
  local options=("$@")
  local file opt preview
  local -n previews_ref="$previews_map_name"

  previews_ref=()
  [[ -d "$root_dir" ]] || return 0

  for opt in "${options[@]}"; do
    previews_ref["$opt"]=""
  done

  while IFS= read -r -d '' file; do
    for opt in "${options[@]}"; do
      if grep -Fq "options.$opt.enable" "$file" || grep -Fq "$opt.enable" "$file"; then
        preview="${previews_ref[$opt]}"
        if [[ -n "$preview" ]]; then
          preview+=$'\n\n'
        fi
        preview+="# $file"$'\n'
        preview+="$(sed -n '1,240p' "$file")"
        previews_ref["$opt"]="$preview"
      fi
    done
  done < <(
    if [[ "$exclude_modules_file" == "true" ]]; then
      find "$root_dir" -type f -name '*.nix' ! -name 'modules.nix' ! -name 'local.nix' -print0
    else
      find "$root_dir" -type f -name '*.nix' -print0
    fi
  )

  for opt in "${options[@]}"; do
    if [[ -z "${previews_ref[$opt]}" ]]; then
      previews_ref["$opt"]="No source file found for $opt."
    fi
  done
}

truncate_field() {
  local text="$1"
  local width="$2"

  if ((width <= 0)); then
    return 0
  fi

  text="${text//$'\t'/  }"
  if ((${#text} > width)); then
    printf '%s' "${text:0:width}"
  else
    printf '%-*s' "$width" "$text"
  fi
}

pick_modules_gum() {
  local title="$1"
  shift
  local options=("$@")
  local selected=""
  local opt
  local gum_args=(
    choose
    --no-limit
    --cursor-prefix '>'
    --selected-prefix '[x] '
    --unselected-prefix '[ ] '
  )

  [[ ${#options[@]} -eq 0 ]] && return 0

  echo
  echo "$title"
  for opt in "${options[@]}"; do
    if [[ "${CURRENT_PICK_DEFAULTS[$opt]:-false}" == "true" ]]; then
      gum_args+=(--selected "$opt")
    fi
  done

  selected="$(gum "${gum_args[@]}" "${options[@]}" || true)"
  printf '%s\n' "$selected" | sed '/^$/d'
}

pick_modules_whiptail() {
  local title="$1"
  local prompt="$2"
  shift 2
  local options=("$@")
  local items=()
  local opt status current
  local out=""

  [[ ${#options[@]} -eq 0 ]] && return 0

  for opt in "${options[@]}"; do
    current="${CURRENT_PICK_DEFAULTS[$opt]:-false}"
    status="OFF"
    [[ "$current" == "true" ]] && status="ON"
    items+=("$opt" "" "$status")
  done

  out="$(whiptail --title "$title" --checklist "$prompt" 22 90 14 "${items[@]}" 3>&1 1>&2 2>&3 || true)"
  out="${out//\"/}"
  printf '%s\n' "$out" | tr ' ' '\n' | sed '/^$/d'
}

pick_modules_native() {
  local title="$1"
  shift
  local options=("$@")
  local total="${#options[@]}"
  local cursor=0
  local preview_scroll=0
  local key key2 key3 i opt mark pointer rows cols size left_width right_width body_rows preview_rows max_preview_scroll viewport row option_index left_line right_line preview_line preview_index footer_line
  local -a selected=()
  local -a preview_lines=()
  local tty="/dev/tty"

  if [[ ! -r "$tty" || ! -w "$tty" ]]; then
    echo "Native TUI requires an interactive terminal (/dev/tty unavailable)." >&2
    exit 1
  fi

  [[ "$total" -eq 0 ]] && return 0

  for ((i = 0; i < total; i++)); do
    opt="${options[$i]}"
    if [[ "${CURRENT_PICK_DEFAULTS[$opt]:-false}" == "true" ]]; then
      selected[$i]=1
    else
      selected[$i]=0
    fi
  done

  while true; do
    size="$(stty size < "$tty" 2>/dev/null || printf '24 100')"
    rows="${size%% *}"
    cols="${size##* }"
    if ((rows < 10)); then
      rows=10
    fi
    if ((cols < 80)); then
      cols=80
    fi
    left_width=$((cols / 2 - 1))
    right_width=$((cols - left_width - 3))
    body_rows=$((rows - 4))

    viewport=0
    if ((cursor >= body_rows)); then
      viewport=$((cursor - body_rows + 1))
    fi

    mapfile -t preview_lines <<< "${CURRENT_PICK_PREVIEWS[${options[$cursor]}]:-No preview available.}"
    preview_rows="${#preview_lines[@]}"
    max_preview_scroll=$((preview_rows - body_rows))
    if ((max_preview_scroll < 0)); then
      max_preview_scroll=0
    fi
    if ((preview_scroll > max_preview_scroll)); then
      preview_scroll="$max_preview_scroll"
    fi

    clear > "$tty"
    echo "$title" > "$tty"
    echo "Use Up/Down to move, Space to toggle, U/D to scroll preview, Enter to submit." > "$tty"
    printf '%s | %s\n' "$(truncate_field "Modules" "$left_width")" "$(truncate_field "Raw Nix source for ${options[$cursor]}" "$right_width")" > "$tty"

    for ((row = 0; row < body_rows; row++)); do
      option_index=$((viewport + row))
      left_line=""
      if ((option_index < total)); then
        if [[ "${selected[$option_index]}" -eq 1 ]]; then
          mark="[x]"
        else
          mark="[ ]"
        fi

        if [[ "$option_index" -eq "$cursor" ]]; then
          pointer=">"
        else
          pointer=" "
        fi

        left_line="$pointer $mark ${options[$option_index]}"
      fi

      preview_index=$((preview_scroll + row))
      if ((preview_index < preview_rows)); then
        preview_line="${preview_lines[$preview_index]}"
      else
        preview_line=""
      fi

      printf '%s | %s\n' "$(truncate_field "$left_line" "$left_width")" "$(truncate_field "$preview_line" "$right_width")" > "$tty"
    done

    footer_line="Preview ${preview_scroll}-$((preview_scroll + body_rows)) of $preview_rows"
    if ((max_preview_scroll > 0)); then
      footer_line+="; U/D scrolls right pane"
    fi
    printf '%s | %s\n' "$(truncate_field "" "$left_width")" "$(truncate_field "$footer_line" "$right_width")" > "$tty"

    IFS= read -rsn1 key < "$tty"

    if [[ -z "$key" ]]; then
      break
    elif [[ "$key" == " " ]]; then
      if [[ "${selected[$cursor]}" -eq 1 ]]; then
        selected[$cursor]=0
      else
        selected[$cursor]=1
      fi
    elif [[ "$key" == "U" || "$key" == "u" ]]; then
      if ((preview_scroll > 0)); then
        ((preview_scroll--))
      fi
    elif [[ "$key" == "D" || "$key" == "d" ]]; then
      if ((preview_scroll < max_preview_scroll)); then
        ((preview_scroll++))
      fi
    elif [[ "$key" == $'\x1b' ]]; then
      IFS= read -rsn1 key2 < "$tty"
      IFS= read -rsn1 key3 < "$tty"
      if [[ "$key2" == "[" ]]; then
        case "$key3" in
          A)
            ((cursor--))
            if ((cursor < 0)); then
              cursor=$((total - 1))
            fi
            preview_scroll=0
            ;;
          B)
            ((cursor++))
            if ((cursor >= total)); then
              cursor=0
            fi
            preview_scroll=0
            ;;
        esac
      fi
    fi
  done

  clear > "$tty"
  for ((i = 0; i < total; i++)); do
    if [[ "${selected[$i]}" -eq 1 ]]; then
      printf '%s\n' "${options[$i]}"
    fi
  done
}

pick_modules() {
  local title="$1"
  local prompt="$2"
  local defaults_map_name="$3"
  shift 3
  local options=("$@")
  local opt
  local -n defaults_ref="$defaults_map_name"

  CURRENT_PICK_DEFAULTS=()
  for opt in "${options[@]}"; do
    CURRENT_PICK_DEFAULTS["$opt"]="${defaults_ref[$opt]:-false}"
  done

  pick_modules_native "$title" "${options[@]}"
}

build_bool_map() {
  local selected_lines="$1"
  shift
  local options=("$@")
  local out=""
  local opt val

  for opt in "${options[@]}"; do
    val="false"
    if grep -Fxq "$opt" <<< "$selected_lines"; then
      val="true"
    fi
    out+="$opt=$val"$'\n'
  done

  printf '%s' "$out"
}

get_state_version() {
  local cfg="$1"
  local line version

  if [[ -f "$cfg" ]]; then
    line="$(grep -E '^[[:space:]]*system\.stateVersion[[:space:]]*=' "$cfg" | head -n 1 || true)"
    if [[ "$line" =~ \"([0-9]{2}\.[0-9]{2})\" ]]; then
      version="${BASH_REMATCH[1]}"
      printf '%s\n' "$version"
      return 0
    fi
  fi

  if command -v nixos-version >/dev/null 2>&1; then
    line="$(nixos-version || true)"
    if [[ "$line" =~ ([0-9]{2}\.[0-9]{2}) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  fi

  printf '25.05\n'
}

render_system_config() {
  local state_version="$1"
  local bool_map="$2"
  local line key value

  cat <<EOF
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  system.stateVersion = "$state_version";
EOF

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    value="${line##*=}"
    printf '  %s.enable = %s;\n' "$key" "$value"
  done <<< "$bool_map"

  cat <<'EOF'
}
EOF
}

render_home_modules() {
  local bool_map="$1"
  local line key value

  cat <<'EOF'
{
EOF

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    value="${line##*=}"
    printf '  %s.enable = %s;\n' "$key" "$value"
  done <<< "$bool_map"

  cat <<'EOF'
}
EOF
}

generate_system_config_content() {
  local module_root="$1"
  local system_cfg_path="$2"
  local state_version selected bool_map
  local -a system_options=()
  local -A system_defaults=()

  mapfile -t system_options < <(discover_enable_options "$module_root")
  discover_source_defaults "$module_root" system_defaults false
  discover_option_previews "$module_root" CURRENT_PICK_PREVIEWS false "${system_options[@]}"

  if [[ ${#system_options[@]} -eq 0 ]]; then
    echo "Warning: no system enable options discovered in $module_root" >&2
  fi

  selected="$(pick_modules "System Modules" "Select system modules to enable" system_defaults "${system_options[@]}")"
  bool_map="$(build_bool_map "$selected" "${system_options[@]}")"
  state_version="$(get_state_version "$system_cfg_path")"

  render_system_config "$state_version" "$bool_map"
}

generate_home_modules_content() {
  local home_root="$1"
  local selected bool_map
  local -a home_options=()
  local -A home_defaults=()

  mapfile -t home_options < <(discover_enable_options "$home_root")
  discover_source_defaults "$home_root" home_defaults true
  discover_option_previews "$home_root" CURRENT_PICK_PREVIEWS true "${home_options[@]}"

  if [[ ${#home_options[@]} -eq 0 ]]; then
    echo "Warning: no home enable options discovered in $home_root" >&2
  fi

  selected="$(pick_modules "Home Manager Modules" "Select home modules to enable" home_defaults "${home_options[@]}")"
  bool_map="$(build_bool_map "$selected" "${home_options[@]}")"

  render_home_modules "$bool_map"
}

main() {
  local SYSTEM_CONFIG_CONTENT HOME_MODULES_CONTENT

  sudo chown -R "$TARGET_USER:$TARGET_GROUP" "$NIXOS_DIR"

  sudo rm -rf "$NIX_MODULES_DIR"
  sudo mkdir -p "$NIX_MODULES_DIR"
  echo Downloading system config...
  SYSTEM_TAR="$(mktemp)"
  curl --fail --location https://github.com/gusjengis/nix-modules/archive/refs/heads/main.tar.gz -o "$SYSTEM_TAR"
  sudo tar -xzf "$SYSTEM_TAR" --strip-components=1 -C "$NIX_MODULES_DIR"
  rm -f "$SYSTEM_TAR"

  sudo chown -R "$TARGET_USER:$TARGET_GROUP" "$NIX_MODULES_DIR"

  echo Generating system module selections...
  SYSTEM_CONFIG_CONTENT="$(generate_system_config_content "$SYSTEM_MODULES_DIR" "$CONFIG_FILE")"
  printf '%s\n' "$SYSTEM_CONFIG_CONTENT" > "$CONFIG_FILE"

  echo Installing system config...
  sudo env NIX_CONFIG="experimental-features = nix-command flakes" nixos-rebuild switch --impure --flake /etc/nix-modules/

  echo Replacing temporary system config with git clone...
  sudo rm -rf "$NIX_MODULES_DIR"
  sudo git clone https://github.com/gusjengis/nix-modules.git "$NIX_MODULES_DIR"
  sudo chown -R "$TARGET_USER:$TARGET_GROUP" "$NIX_MODULES_DIR"

  printf '%s\n' "$SYSTEM_CONFIG_CONTENT" > "$CONFIG_FILE"

  rm -rf "$HOME_MANAGER_DIR"
  mkdir -p "$HOME_MANAGER_DIR"
  echo Downloading home config...
  git clone https://github.com/gusjengis/home-manager.git "$HOME_MANAGER_DIR"

  echo Generating home-manager module selections...
  HOME_MODULES_CONTENT="$(generate_home_modules_content "$HOME_MANAGER_DIR")"
  printf '%s\n' "$HOME_MODULES_CONTENT" > "$HOME_MODULES_FILE"

  sudo chown -R "$TARGET_USER:$TARGET_GROUP" "$HOME_DIR"

  echo Installing home config...
  sudo -u "$TARGET_USER" env NIX_CONFIG="experimental-features = nix-command flakes" home-manager switch --impure --flake "$HOME_MANAGER_DIR/"
}

main "$@"
