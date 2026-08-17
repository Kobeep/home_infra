#!/bin/bash

echo "INFO=> Do you want to scan the local network to gather data about machines? (yes/no)"
read -r answer

answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

if [[ "$answer" != "yes" ]]; then
    echo "INFO=> Operation cancelled."
    exit 0
fi

echo "INFO=> Provide network address in CIDR format (e.g., 192.168.1.0/24):"
read -r ip_address

echo "INFO=> Scanning network: $ip_address..."

pc_hosts=()
server_hosts=()
modem_hosts=()

while read -r ip raw_hostname; do
    [ -z "$ip" ] && continue

    hostname="${raw_hostname//[()]/}"

    hostname="${hostname%.home}"
    hostname="${hostname%.lan}"

    if [ -z "$hostname" ]; then
        hostname="$ip"
    fi

    record="$hostname|$ip"

    if [[ "$hostname" == *"Kobee"* || "$hostname" == *"Kinga"* || "$hostname" == *"mac"* ]]; then
        pc_hosts+=("$record")
    elif [[ "$ip" == *.1 || "$ip" == *.254 || "$ip" == *.2 ]]; then
        modem_hosts+=("$record")
    else
        server_hosts+=("$record")
    fi
done < <(nmap -sn "$ip_address" -oG - | awk '/Up$/{print $2, $3}')

if [ ${#pc_hosts[@]} -eq 0 ] && [ ${#server_hosts[@]} -eq 0 ] && [ ${#modem_hosts[@]} -eq 0 ]; then
    echo "INFO=> No active hosts found."
    exit 0
fi

mkdir -p ansible
inventory_file="ansible/inventory.yml"

cat <<EOF > "$inventory_file"
all:
  children:
EOF

if [ -n "${pc_hosts[*]:-}" ]; then
    echo "    pc:" >> "$inventory_file"
    echo "      hosts:" >> "$inventory_file"
    for record in "${pc_hosts[@]:-}"; do
        [ -n "$record" ] || continue
        hname="${record%|*}"
        hip="${record#*|}"
        echo "        $hname:" >> "$inventory_file"
        echo "          ansible_host: $hip" >> "$inventory_file"
    done
fi

if [ -n "${server_hosts[*]:-}" ]; then
    echo "    server:" >> "$inventory_file"
    echo "      hosts:" >> "$inventory_file"
    for record in "${server_hosts[@]:-}"; do
        [ -n "$record" ] || continue
        hname="${record%|*}"
        hip="${record#*|}"
        echo "        $hname:" >> "$inventory_file"
        echo "          ansible_host: $hip" >> "$inventory_file"
        echo "          ansible_user: server" >> "$inventory_file"
        echo "          ansible_ssh_private_key_file: ~/.ssh/server/id_rsa" >> "$inventory_file"
    done
fi

if [ -n "${modem_hosts[*]:-}" ]; then
    echo "    modem:" >> "$inventory_file"
    echo "      hosts:" >> "$inventory_file"
    for record in "${modem_hosts[@]:-}"; do
        [ -n "$record" ] || continue
        hname="${record%|*}"
        hip="${record#*|}"
        echo "        $hname:" >> "$inventory_file"
        echo "          ansible_host: $hip" >> "$inventory_file"
    done
fi

echo "INFO=> Ansible inventory generated successfully in $inventory_file"
