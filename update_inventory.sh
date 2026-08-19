#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CLASSIFY_CONF="${CLASSIFY_CONF:-$SCRIPT_DIR/classify.conf}"

# Everything Ansible-related lives under <repo_root>/ansible, regardless of
# which directory the script is invoked from.
ANSIBLE_DIR="${ANSIBLE_DIR:-$SCRIPT_DIR/ansible}"
STATE_FILE="${STATE_FILE:-$ANSIBLE_DIR/.host_state.tsv}"
INVENTORY_FILE="$ANSIBLE_DIR/inventory.yml"
GROUP_VARS_DIR="$ANSIBLE_DIR/group_vars"
HOST_VARS_DIR="$ANSIBLE_DIR/host_vars"
DEFAULT_GROUP="server"
PING_TIMEOUT=1

declare -A META_CHILDREN=(
    [infra]="server modem"
    [clients]="pc phone other"
)
META_ORDER=(infra clients)
KNOWN_LEAVES="server modem pc phone other"

echo "INFO=> Do you want to scan the local network to gather data about machines? (yes/no)"
read -r answer
answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

if [[ "$answer" != "yes" ]]; then
    echo "INFO=> Operation cancelled."
    exit 0
fi

if [ ! -f "$CLASSIFY_CONF" ]; then
    echo "ERROR=> Classification config not found at $CLASSIFY_CONF"
    exit 1
fi

mkdir -p "$ANSIBLE_DIR"

# --- Detect the LAN CIDR off the default route interface ---
iface=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
if [ -z "${iface:-}" ]; then
    echo "ERROR=> Could not determine default network interface."
    exit 1
fi

cidr=$(ip -o -f inet addr show dev "$iface" 2>/dev/null | awk '{print $4; exit}')
if [ -z "${cidr:-}" ]; then
    echo "ERROR=> Could not determine CIDR for interface $iface."
    exit 1
fi

echo "INFO=> Scanning network: $cidr (via $iface)..."

euid=$(id -u)
run_whole_script_as_root=0
[ "$euid" -eq 0 ] && run_whole_script_as_root=1

# MAC addresses need raw-socket access. Rather than requiring the WHOLE
# script to run as root (which would leave inventory.yml, group_vars/, etc.
# owned by root and unreadable by your normal user), elevate only the nmap
# call itself. Everything this script writes still happens as you.
NMAP_CMD=(nmap -sn "$cidr")
if [ "$run_whole_script_as_root" -eq 0 ]; then
    if command -v sudo &> /dev/null; then
        echo "INFO=> Elevating only the nmap scan via sudo (for MAC address detection)..."
        NMAP_CMD=(sudo nmap -sn "$cidr")
    else
        echo "WARNING=> No sudo available — no MAC addresses will be captured."
        echo "WARNING=> That disables vendor-based classification AND stable"
        echo "WARNING=> host identity across DHCP changes."
    fi
fi

# --- Parse standard nmap output into ip|hostname|vendor|mac records ---
scan_output=$("${NMAP_CMD[@]}" 2>/dev/null)

records=$(echo "$scan_output" | awk '
/^Nmap scan report for/ {
    if (ip != "") { print ip "|" hostname "|" vendor "|" mac }
    line = $0
    sub(/^Nmap scan report for /, "", line)
    if (line ~ /\(/) {
        split(line, parts, "[()]")
        hostname = parts[1]
        gsub(/ +$/, "", hostname)
        ip = parts[2]
    } else {
        ip = line
        hostname = ""
    }
    vendor = ""
    mac = ""
    next
}
/^MAC Address:/ {
    rest = $0
    sub(/^MAC Address: /, "", rest)
    split(rest, a, " \\(")
    mac = a[1]
    vendor = a[2]
    sub(/\)$/, "", vendor)
}
END {
    if (ip != "") print ip "|" hostname "|" vendor "|" mac
}
')

if [ -z "$records" ]; then
    echo "INFO=> No active hosts found."
    exit 0
fi

# --- Load classification rules: group|field|pattern ---
declare -a RULE_GROUP RULE_FIELD RULE_PATTERN
while IFS='|' read -r g f p; do
    [[ -z "$g" || "$g" == \#* ]] && continue
    RULE_GROUP+=("$g")
    RULE_FIELD+=("$f")
    RULE_PATTERN+=("$p")
done < "$CLASSIFY_CONF"

classify() {
    local hostname="${1,,}" ip="$2" vendor="${3,,}"
    local i field pattern value
    for i in "${!RULE_GROUP[@]}"; do
        field="${RULE_FIELD[$i]}"
        pattern="${RULE_PATTERN[$i],,}"
        case "$field" in
            hostname) value="$hostname" ;;
            ip)       value="$ip" ;;
            vendor)   value="$vendor" ;;
            *)        continue ;;
        esac
        if [[ "$value" == *"$pattern"* ]]; then
            echo "${RULE_GROUP[$i]}"
            return
        fi
    done
    echo "$DEFAULT_GROUP"
}

# --- Load persisted MAC -> stable-name mapping ---
declare -A MAC_NAME
if [ -f "$STATE_FILE" ]; then
    while IFS=$'\t' read -r mac name; do
        [ -z "$mac" ] && continue
        MAC_NAME["$mac"]="$name"
    done < "$STATE_FILE"
fi

declare -A GROUPED   # group name -> newline separated "name|ip|mac"
unresolved_no_mac=0
got_mac=0

while IFS='|' read -r ip raw_hostname vendor mac; do
    [ -z "$ip" ] && continue

    hostname="${raw_hostname//[()]/}"
    hostname="${hostname%.home}"
    hostname="${hostname%.lan}"
    [ -z "$hostname" ] && hostname="$ip"

    group=$(classify "$hostname" "$ip" "${vendor:-}")

    if [ -n "${mac:-}" ]; then
        got_mac=1
        if [ -n "${MAC_NAME[$mac]:-}" ]; then
            # Known device. Only overwrite the stored name if we resolved a
            # *real* hostname this time (never downgrade a good name to an IP).
            if [ "$hostname" != "$ip" ] && [ "$hostname" != "${MAC_NAME[$mac]}" ]; then
                MAC_NAME["$mac"]="$hostname"
            fi
            name="${MAC_NAME[$mac]}"
        else
            MAC_NAME["$mac"]="$hostname"
            name="$hostname"
        fi
    else
        name="$hostname"
        unresolved_no_mac=1
    fi

    GROUPED["$group"]+="$name|$ip|${mac:-}"$'\n'
done <<< "$records"

# --- Persist updated MAC -> name state ---
if [ "$got_mac" -eq 1 ]; then
    {
        for mac in "${!MAC_NAME[@]}"; do
            printf '%s\t%s\n' "$mac" "${MAC_NAME[$mac]}"
        done
    } | sort > "$STATE_FILE"
fi

# --- Back up any existing inventory instead of silently clobbering it ---
if [ -f "$INVENTORY_FILE" ]; then
    cp "$INVENTORY_FILE" "${INVENTORY_FILE}.bak.$(date +%Y%m%d%H%M%S)"
fi

emit_hosts() {
    local group="$1" indent="$2"
    while IFS='|' read -r name ip mac; do
        [ -z "$name" ] && continue
        if [ -n "$mac" ]; then
            printf '%s%s:\n%s  ansible_host: %s  # mac: %s\n' "$indent" "$name" "$indent" "$ip" "$mac"
        else
            printf '%s%s:\n%s  ansible_host: %s\n' "$indent" "$name" "$indent" "$ip"
        fi
    done <<< "${GROUPED[$group]}"
}

{
    echo "all:"
    echo "  children:"
    for meta in "${META_ORDER[@]}"; do
        # Only emit the meta-group if at least one of its children has hosts
        has_hosts=0
        for leaf in ${META_CHILDREN[$meta]}; do
            [ -n "${GROUPED[$leaf]:-}" ] && has_hosts=1
        done
        [ "$has_hosts" -eq 0 ] && continue

        echo "    $meta:"
        echo "      children:"
        for leaf in ${META_CHILDREN[$meta]}; do
            [ -z "${GROUPED[$leaf]:-}" ] && continue
            echo "        $leaf:"
            echo "          hosts:"
            emit_hosts "$leaf" "            "
        done
    done

    # Any classify.conf group not wired into META_CHILDREN goes straight
    # under 'all' so it's never silently dropped.
    for group in "${!GROUPED[@]}"; do
        if [[ ! " $KNOWN_LEAVES " == *" $group "* ]]; then
            echo "WARNING=> Group '$group' has no parent mapping — placing directly under 'all'. Add it to META_CHILDREN in the script to nest it." >&2
            echo "    $group:"
            echo "      hosts:"
            emit_hosts "$group" "        "
        fi
    done
} > "$INVENTORY_FILE"

# --- Scaffold group_vars once per group; never overwrite existing files ---
mkdir -p "$GROUP_VARS_DIR"

if [ ! -f "$GROUP_VARS_DIR/all.yml" ]; then
    cat > "$GROUP_VARS_DIR/all.yml" <<'EOF'
# Vars shared by every host in the inventory.
ansible_python_interpreter: auto_silent
EOF
    echo "INFO=> Created $GROUP_VARS_DIR/all.yml"
fi

for group in "${!GROUPED[@]}"; do
    gv_file="$GROUP_VARS_DIR/$group.yml"
    [ -f "$gv_file" ] && continue
    case "$group" in
        server)
            cat > "$gv_file" <<'EOF'
# Default connection settings applied to every host in the 'server' group.
# If a specific host needs a different user/key, do NOT edit this file —
# instead create/edit ansible/host_vars/<hostname>.yml, which overrides
# this per-host. This file is just the fallback for the common case.
ansible_user: server
ansible_ssh_private_key_file: ~/.ssh/server/id_rsa
EOF
            ;;
        *)
            cat > "$gv_file" <<EOF
# group_vars for '$group' — shared defaults for every host in this group.
# For a host that needs different settings than the rest of the group,
# use ansible/host_vars/<hostname>.yml instead — it takes priority over
# this file for that one host.
# ansible_user: someuser
# ansible_ssh_private_key_file: ~/.ssh/id_rsa
EOF
            ;;
    esac
    echo "INFO=> Created $gv_file"
done

# --- Scaffold host_vars per host; this is where per-host overrides go ---
# (different SSH user/key for one specific PC, server, router, etc.)
mkdir -p "$HOST_VARS_DIR"
for group in "${!GROUPED[@]}"; do
    while IFS='|' read -r name ip mac; do
        [ -z "$name" ] && continue
        hv_file="$HOST_VARS_DIR/$name.yml"
        [ -f "$hv_file" ] && continue
        cat > "$hv_file" <<EOF
# host_vars for '$name' (group: $group, ip: $ip)
# These override ansible/group_vars/$group.yml for this host only.
# Uncomment and set whatever differs for this specific machine:
#
# ansible_user: someuser
# ansible_ssh_private_key_file: ~/.ssh/id_rsa
# ansible_port: 22
EOF
        echo "INFO=> Created $hv_file"
    done <<< "${GROUPED[$group]}"
done

echo "INFO=> Pinging discovered hosts to check availability..."
for group in "${!GROUPED[@]}"; do
    while IFS='|' read -r name ip mac; do
        [ -z "$name" ] && continue
        if ping -c 1 -W "$PING_TIMEOUT" "$ip" &> /dev/null; then
            echo "INFO=> Host $name ($ip) [$group] is reachable."
        else
            echo "WARNING=> Host $name ($ip) [$group] is not reachable."
        fi
    done <<< "${GROUPED[$group]}"
done

if [ "$unresolved_no_mac" -eq 1 ]; then
    echo "WARNING=> Some hosts had no MAC address (unprivileged scan) and were"
    echo "WARNING=> keyed by IP only — their identity may not be stable across DHCP renewals."
fi

if command -v ansible-inventory &> /dev/null; then
    echo "INFO=> Validating inventory with ansible-inventory..."
    if ansible-inventory -i "$INVENTORY_FILE" --list &> /dev/null; then
        echo "INFO=> Inventory syntax OK."
    else
        echo "ERROR=> ansible-inventory failed to parse $INVENTORY_FILE — check the file."
    fi
fi

# Safety net: if you ran the WHOLE script under sudo (instead of letting it
# elevate only the nmap call), hand ownership of everything it wrote back to
# the user who actually invoked sudo, so it stays readable/writable by you.
if [ "$run_whole_script_as_root" -eq 1 ] && [ -n "${SUDO_UID:-}" ] && [ -n "${SUDO_GID:-}" ]; then
    chown -R "$SUDO_UID:$SUDO_GID" "$ANSIBLE_DIR"
    echo "INFO=> Restored ownership of $ANSIBLE_DIR to uid $SUDO_UID (the user who ran sudo)."
elif [ "$run_whole_script_as_root" -eq 1 ]; then
    echo "WARNING=> Running as root but \$SUDO_UID is unset — files under $ANSIBLE_DIR"
    echo "WARNING=> remain root-owned. Fix with: sudo chown -R \$USER:\$USER $ANSIBLE_DIR"
fi

echo "INFO=> Ansible inventory generated successfully in $INVENTORY_FILE"
