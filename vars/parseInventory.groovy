#!/usr/bin/env groovy

/**
 * Parse Ansible inventory and extract host configuration
 * @param inventoryFile Path to the inventory YAML file
 * @param targetHost Target hostname to extract
 * @param targetGroup Target group (windows/linux)
 * @return Map containing host configuration
 */
def call(String inventoryFile, String targetHost, String targetGroup) {
    try {
        def inventoryJson = sh(script: """
            python3 -c '
import sys, yaml, json
target = "${targetHost}"
group = "${targetGroup}"
try:
    with open("${inventoryFile}") as f:
        inv = yaml.safe_load(f)
    
    host_config = None
    if group in inv.get("all", {}).get("children", {}):
        group_data = inv["all"]["children"][group]
        if "hosts" in group_data and target in group_data["hosts"]:
            host_config = group_data["hosts"][target]
    
    if host_config is None:
        sys.exit(f"Host not found in {group} group: {target}")
    
    print(json.dumps(host_config))
except Exception as e:
    sys.exit(f"Error parsing inventory: {e}")
            '
        """, returnStdout: true).trim()
        
        return readJSON(text: inventoryJson)
    } catch (Exception e) {
        error "❌ Failed to parse inventory: ${e.message}"
    }
}