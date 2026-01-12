#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Home Lab Deployment Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if Ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${YELLOW}Ansible not found. Installing...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install ansible
    else
        sudo apt update && sudo apt install -y ansible
    fi
fi

# Check if inventory exists
if [ ! -f "ansible/inventory.yml" ]; then
    echo -e "${RED}Error: ansible/inventory.yml not found${NC}"
    echo "Please create it first with your server details"
    exit 1
fi

# Prompt for server IP if not set
echo -e "${YELLOW}Configure your server IP in ansible/inventory.yml before running${NC}"
read -p "Have you configured ansible/inventory.yml? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Please configure ansible/inventory.yml first${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Starting deployment...${NC}"
echo ""

# Run Ansible playbook
ansible-playbook \
    -i ansible/inventory.yml \
    ansible/playbooks/full-setup.yml \
    -v

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Access Dashy dashboard to see all services${NC}"
echo ""
