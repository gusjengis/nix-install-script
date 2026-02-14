#!/usr/bin/env bash
set -euo pipefail

SYSTEM_MODULES_DIR="${SYSTEM_MODULES_DIR:-/etc/nix-modules/nixosModules}"
SYSTEM_CONFIG_PATH="${SYSTEM_CONFIG_PATH:-/etc/nixos/configuration.nix}"

declare -A SOURCE_DEFAULTS=()
declare -A CURRENT_PICK_DEFAULTS=()

usage() {
  cat <<'EOF'
Usage: test-system-module-selector.sh [options]

Scans NixOS module options, presents a TUI checklist,
then prints the configuration.nix it would generate.

Options:
  --system-modules-dir PATH   System module root (default: /etc/nix-modules/nixosModules)
  --system-config PATH        System config path for stateVersion lookup (default: /etc/nixos/configuration.nix)
  -h, --help                  Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --system-modules-dir)
        SYSTEM_MODULES_DIR="$2"
        shift 2
        ;;
      --system-config)
        SYSTEM_CONFIG_PATH="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

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
  local file line opt value
  local in_option_block=0
  local current_option=""

  [[ -d "$root_dir" ]] || return 0

  while IFS= read -r -d '' file; do
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_.-]+)\.enable[[:space:]]*=[[:space:]]*lib\.mkDefault[[:space:]]*(true|false)[[:space:]]*\; ]]; then
        opt="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        SOURCE_DEFAULTS["$opt"]="$value"
      fi

      if [[ "$line" =~ ^[[:space:]]*options\.([A-Za-z0-9_.-]+)\.enable[[:space:]]*=[[:space:]]*lib\.mkEnableOption ]]; then
        in_option_block=1
        current_option="${BASH_REMATCH[1]}"

        if [[ "$line" =~ default[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*\; ]]; then
          value="${BASH_REMATCH[1]}"
          SOURCE_DEFAULTS["$current_option"]="$value"
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
          SOURCE_DEFAULTS["$current_option"]="$value"
        fi

        if [[ "$line" == *"};"* || "$line" == *";"* ]]; then
          in_option_block=0
          current_option=""
        fi
      fi
    done < "$file"
  done < <(find "$root_dir" -type f -name '*.nix' -print0)
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
  local key key2 key3 i opt mark pointer
  local -a selected=()
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
    clear > "$tty"
    echo "$title" > "$tty"
    echo "Use Up/Down to move, Space to toggle, Enter to submit." > "$tty"
    echo > "$tty"

    for ((i = 0; i < total; i++)); do
      if [[ "${selected[$i]}" -eq 1 ]]; then
        mark="[x]"
      else
        mark="[ ]"
      fi

      if [[ "$i" -eq "$cursor" ]]; then
        pointer=">"
      else
        pointer=" "
      fi

      printf "%s %s %s\n" "$pointer" "$mark" "${options[$i]}" > "$tty"
    done

    IFS= read -rsn1 key < "$tty"

    if [[ -z "$key" ]]; then
      break
    elif [[ "$key" == " " ]]; then
      if [[ "${selected[$cursor]}" -eq 1 ]]; then
        selected[$cursor]=0
      else
        selected[$cursor]=1
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
            ;;
          B)
            ((cursor++))
            if ((cursor >= total)); then
              cursor=0
            fi
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
  shift 2
  local options=("$@")
  local opt

  CURRENT_PICK_DEFAULTS=()
  for opt in "${options[@]}"; do
    CURRENT_PICK_DEFAULTS["$opt"]="${SOURCE_DEFAULTS[$opt]:-false}"
  done

  if command -v gum >/dev/null 2>&1; then
    pick_modules_gum "$title (toggle with space, confirm with enter)" "${options[@]}"
    return 0
  fi

  if command -v whiptail >/dev/null 2>&1; then
    pick_modules_whiptail "$title" "$prompt" "${options[@]}"
    return 0
  fi

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

main() {
  parse_args "$@"

  mapfile -t system_options < <(discover_enable_options "$SYSTEM_MODULES_DIR")
  discover_source_defaults "$SYSTEM_MODULES_DIR"

  if [[ ${#system_options[@]} -eq 0 ]]; then
    echo "Warning: no system enable options discovered in $SYSTEM_MODULES_DIR" >&2
  fi

  selected="$(pick_modules "System Modules" "Select system modules to enable" "${system_options[@]}")"
  state_version="$(get_state_version "$SYSTEM_CONFIG_PATH")"
  bool_map="$(build_bool_map "$selected" "${system_options[@]}")"

  render_system_config "$state_version" "$bool_map"
}

main "$@"
