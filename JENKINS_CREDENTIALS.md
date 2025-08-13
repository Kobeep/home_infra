# Jenkins Credentials Configuration Guide

This guide explains how to configure Jenkins credentials for the home infrastructure pipelines to work securely without hardcoded secrets.

## Required Credentials

The transformed pipelines require the following Jenkins credentials to be configured:

### 1. Jenkins Agent Secret
- **Credential ID**: `jenkins-agent-secret`
- **Type**: Secret text
- **Value**: The Jenkins agent secret token for the 'slave' node
- **Usage**: Used by the agent management pipeline to securely start offline agents

### 2. Jenkins Master URL  
- **Credential ID**: `jenkins-master-url`
- **Type**: Secret text
- **Value**: The complete Jenkins master URL (e.g., `http://192.168.0.122:8080/`)
- **Usage**: Used by the agent management pipeline to connect agents to the correct master

### 3. Git Repository Credentials
- **Credential ID**: `7a5fcd35-3a38-4511-a275-881c11e6625d` (existing)
- **Type**: Username with password
- **Usage**: Used by backup pipeline to commit and push backup data to the repository

## How to Configure Credentials

### Step 1: Access Jenkins Credentials
1. Log into Jenkins web interface
2. Navigate to "Manage Jenkins" → "Manage Credentials"
3. Select the appropriate domain (usually "Global")

### Step 2: Add Jenkins Agent Secret
1. Click "Add Credentials"
2. Select "Secret text" as the kind
3. Set ID to: `jenkins-agent-secret`
4. In the "Secret" field, enter the agent secret token
   - To find the current secret: Go to Jenkins → Manage Nodes → slave → configure
   - Or generate a new one if needed
5. Add description: "Jenkins agent secret for slave node"
6. Click "OK"

### Step 3: Add Jenkins Master URL
1. Click "Add Credentials"
2. Select "Secret text" as the kind  
3. Set ID to: `jenkins-master-url`
4. In the "Secret" field, enter the complete Jenkins URL (e.g., `http://192.168.0.122:8080/`)
5. Add description: "Jenkins master URL for agent connections"
6. Click "OK"

### Step 4: Verify Git Credentials
1. Ensure the credential ID `7a5fcd35-3a38-4511-a275-881c11e6625d` exists
2. It should be a "Username with password" credential
3. Username should be your Git username
4. Password should be a personal access token (not your Git password)

## Security Best Practices

### Agent Secret Management
- **Regenerate Regularly**: Change the agent secret periodically for security
- **Restrict Access**: Limit who can view/modify these credentials
- **Monitor Usage**: Check Jenkins logs for unauthorized agent connection attempts

### Git Credentials
- **Use Personal Access Token**: Never use your actual Git password
- **Minimal Permissions**: Grant only the necessary repository permissions
- **Token Expiration**: Set appropriate expiration dates for access tokens

### URL Configuration
- **Internal Networks**: Use internal IP addresses when possible
- **HTTPS Preferred**: Use HTTPS URLs when available
- **Network Security**: Ensure proper firewall rules are in place

## Troubleshooting

### Agent Connection Issues
If the agent management pipeline fails:

1. **Check Agent Secret**:
   ```
   Error: "403 Forbidden" or "401 Unauthorized"
   Solution: Verify the jenkins-agent-secret credential has the correct value
   ```

2. **Check Master URL**:
   ```
   Error: "Connection refused" or "Host unreachable"
   Solution: Verify the jenkins-master-url credential has the correct URL and port
   ```

3. **Check Network Connectivity**:
   ```
   Error: Timeout errors
   Solution: Ensure network connectivity between Jenkins master and agent
   ```

### Git Push Issues
If the backup pipeline fails to push:

1. **Check Git Credentials**:
   ```
   Error: "Authentication failed"
   Solution: Verify the Git credentials are correct and have push permissions
   ```

2. **Check Token Permissions**:
   ```
   Error: "Permission denied"
   Solution: Ensure the personal access token has 'repo' scope permissions
   ```

3. **Check Repository Access**:
   ```
   Error: "Repository not found"
   Solution: Verify the token has access to the repository
   ```

## Migration from Legacy Setup

If you're migrating from the old hardcoded setup:

### 1. Identify Current Values
- Note the current agent secret from the old Jenkinsfile
- Note the current Jenkins URL from the old Jenkinsfile
- Verify the Git credentials are working

### 2. Create New Credentials
- Follow the configuration steps above
- Use the same values as the hardcoded ones initially

### 3. Test Migration
- Run the agent management pipeline to test agent credentials
- Run the backup pipeline to test Git credentials
- Verify all pipelines work with the new credential system

### 4. Security Cleanup
- Remove any remaining hardcoded values from old files
- Update any documentation that references the old setup
- Consider regenerating secrets for improved security

## Validation

To verify your credentials are configured correctly:

### 1. Test Agent Management
- Run the "autorun_node" pipeline
- Check that it can detect agent status and start if needed
- Verify no credential-related errors in the logs

### 2. Test Backup Pipeline
- Run the "jf" (backup) pipeline
- Check that it can commit and push changes
- Verify no authentication errors

### 3. Test Deployment Pipelines
- Run a test deployment to a Linux or Windows host
- Verify SSH/WinRM credentials are handled securely
- Check that no sensitive data appears in logs

## Additional Security Considerations

### Credential Rotation
- Plan regular rotation of all credentials
- Update documentation when credentials change
- Test pipelines after credential updates

### Access Control
- Limit Jenkins credential access to necessary users only
- Use role-based access control where possible
- Audit credential usage regularly

### Monitoring
- Monitor Jenkins logs for credential-related errors
- Set up alerts for authentication failures
- Review credential usage patterns regularly

By following this guide, your Jenkins instance will be configured with secure credential management, eliminating the security risks of hardcoded secrets while maintaining full pipeline functionality.