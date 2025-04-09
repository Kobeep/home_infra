pipeline {
  agent slave

  parameters {
    booleanParam(name: 'RUN_CONNECTION_CHECK', defaultValue: true, description: 'Check SSH connectivity to the target host')
    booleanParam(name: 'COPY_SSH_KEY', defaultValue: true, description: 'Copy SSH public key to the target host')
    booleanParam(name: 'RUN_ANSIBLE', defaultValue: true, description: 'Run Ansible playbook')

    string(name: 'TARGET_HOST', defaultValue: '192.168.1.100', description: 'IP address or hostname of the target server')
    string(name: 'TARGET_USER', defaultValue: 'ubuntu', description: 'SSH username for the target host')
    string(name: 'SSH_PUBLIC_KEY_PATH', defaultValue: '~/.ssh/id_rsa.pub', description: 'Path to your SSH public key')

    string(name: 'ANSIBLE_INVENTORY', defaultValue: 'ansible/inventory/hosts.yml', description: 'Path to your Ansible inventory file')
    string(name: 'ANSIBLE_PLAYBOOK', defaultValue: 'ansible/playbooks/playbook.yml', description: 'Path to your Ansible playbook')
  }

  stages {

    stage('🔌 Check SSH Connection') {
      when {
        expression { params.RUN_CONNECTION_CHECK }
      }
      steps {
        script {
          sh './scripts/01_check_connection.sh ' + params.TARGET_HOST
        }
      }
    }

    stage('🔑 Copy SSH Public Key') {
      when {
        expression { params.COPY_SSH_KEY }
      }
      steps {
        script {
          sh './scripts/02_copy_ssh_key.sh ' + params.TARGET_HOST + ' ' + params.TARGET_USER + ' ' + params.SSH_PUBLIC_KEY_PATH
        }
      }
    }

    stage('🚀 Run Ansible Playbook') {
      when {
        expression { params.RUN_ANSIBLE }
      }
      steps {
        script {
          sh './scripts/03_run_ansible.sh ' + params.ANSIBLE_INVENTORY + ' ' + params.ANSIBLE_PLAYBOOK
        }
      }
    }
  }

  post {
    success {
      echo '✅ Pipeline completed successfully.'
    }
    failure {
      echo '❌ Pipeline failed.'
    }
    always {
      echo '🏁 Pipeline finished.'
    }
  }
}
