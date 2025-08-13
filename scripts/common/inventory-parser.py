#!/usr/bin/env python3
"""
Ansible Inventory Parser
Parses YAML inventory files and extracts host configuration information.
"""
import sys
import yaml
import json
import argparse
from pathlib import Path


def parse_inventory(inventory_file, target_host, target_group=None):
    """
    Parse inventory file and return host configuration.
    
    Args:
        inventory_file (str): Path to the inventory YAML file
        target_host (str): Target host name to find
        target_group (str): Optional target group (linux/windows)
    
    Returns:
        dict: Host configuration dictionary
    
    Raises:
        SystemExit: If host not found or file not accessible
    """
    try:
        with open(inventory_file, 'r') as f:
            inventory = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"ERROR: Inventory file not found: {inventory_file}", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"ERROR: Invalid YAML in inventory file: {e}", file=sys.stderr)
        sys.exit(1)
    
    if 'all' not in inventory or 'children' not in inventory['all']:
        print("ERROR: Invalid inventory structure - missing 'all.children'", file=sys.stderr)
        sys.exit(1)
    
    host_config = None
    found_group = None
    
    # Search in specific group if provided
    if target_group:
        groups = [target_group]
    else:
        groups = inventory['all']['children'].keys()
    
    for group_name in groups:
        group = inventory['all']['children'].get(group_name, {})
        if 'hosts' in group and target_host in group['hosts']:
            host_config = group['hosts'][target_host]
            found_group = group_name
            break
    
    if host_config is None:
        if target_group:
            print(f"ERROR: Host '{target_host}' not found in group '{target_group}'", file=sys.stderr)
        else:
            print(f"ERROR: Host '{target_host}' not found in any group", file=sys.stderr)
        sys.exit(1)
    
    # Add metadata
    host_config['_group'] = found_group
    host_config['_host'] = target_host
    
    return host_config


def list_hosts(inventory_file, target_group=None):
    """
    List all hosts in inventory or specific group.
    
    Args:
        inventory_file (str): Path to the inventory YAML file
        target_group (str): Optional target group to filter
    
    Returns:
        list: List of host names
    """
    try:
        with open(inventory_file, 'r') as f:
            inventory = yaml.safe_load(f)
    except (FileNotFoundError, yaml.YAMLError):
        return []
    
    hosts = []
    children = inventory.get('all', {}).get('children', {})
    
    if target_group:
        groups = [target_group] if target_group in children else []
    else:
        groups = children.keys()
    
    for group_name in groups:
        group = children[group_name]
        if 'hosts' in group:
            hosts.extend(group['hosts'].keys())
    
    return sorted(set(hosts))


def main():
    parser = argparse.ArgumentParser(description='Parse Ansible inventory files')
    parser.add_argument('inventory_file', help='Path to inventory YAML file')
    parser.add_argument('target_host', nargs='?', help='Target host name (not needed with --list-hosts)')
    parser.add_argument('--group', help='Target group (linux/windows)')
    parser.add_argument('--list-hosts', action='store_true', 
                       help='List all hosts instead of parsing specific host')
    
    args = parser.parse_args()
    
    if args.list_hosts:
        hosts = list_hosts(args.inventory_file, args.group)
        print(json.dumps(hosts))
    else:
        if not args.target_host:
            parser.error("target_host is required when not using --list-hosts")
        host_config = parse_inventory(args.inventory_file, args.target_host, args.group)
        print(json.dumps(host_config))


if __name__ == '__main__':
    main()