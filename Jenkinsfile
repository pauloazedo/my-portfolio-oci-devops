pipeline {
  agent any

  parameters {
    choice(name: 'CLOUD_PROVIDER', choices: ['oci', 'aws', 'gcp', 'azure'], description: 'Target cloud provider')
  }

  environment {
    SSH_KEY_PATH = "/var/jenkins_home/.ssh/id_rsa"
    ANSIBLE_REMOTE_USER = "devops"
    JENKINS_MARKER = "/var/jenkins_home/.jenkins_self_deploy"
  }

  options {
    timestamps()
    ansiColor('xterm')
  }

  stages {
    stage('Prepare Workspace') {
      steps {
        cleanWs()
      }
    }

    stage('Checkout') {
      steps {
        checkout([
          $class: 'GitSCM',
          branches: [[name: '*/uat']],
          userRemoteConfigs: [[url: 'https://github.com/pauloazedo/my-portfolio-oci-devops.git']]
        ])
      }
    }

    stage('Set Image Tag') {
      steps {
        dir('') {
          script {
            def tag = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
            writeFile file: 'image_tag.txt', text: tag
          }
        }
      }
    }

    stage('Sync frontend code to UAT server') {
      steps {
        dir('') {
          script {
            def tag = readFile('image_tag.txt').trim()
            def hostname = "${params.CLOUD_PROVIDER}.uat.pauloazedo.dev"

            sh """
              rsync -az --delete \
                -e "ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=accept-new" \
                ./my-portfolio/frontend/ ${ANSIBLE_REMOTE_USER}@${hostname}:/home/devops/frontend
            """
          }
        }
      }
    }

    stage('Trigger Ansible Deployment') {
      steps {
        dir('') {
          script {
            def tag = readFile('image_tag.txt').trim()
            def inventory = "ansible/inventory/${params.CLOUD_PROVIDER}.ini"

            sh """
              touch ${JENKINS_MARKER}

              export ANSIBLE_SSH_ARGS="-i ${SSH_KEY_PATH} -o StrictHostKeyChecking=accept-new"
              export ANSIBLE_REMOTE_USER=${ANSIBLE_REMOTE_USER}

              /home/jenkins/venv/bin/ansible-playbook -i ${inventory} ansible/uat.yml \
                --limit uat \
                --tags uat_site \
                --extra-vars "cloud_provider=${params.CLOUD_PROVIDER} \
                              uat_site_image_tag=${tag}"
            """
          }
        }
      }
    }
  }

  post {
    success {
      script {
        def tag = readFile('image_tag.txt').trim()
        echo "✅ Deployed ${tag} to ${params.CLOUD_PROVIDER}.uat.pauloazedo.dev"
      }
    }
    failure {
      echo "❌ Deployment failed for ${params.CLOUD_PROVIDER}"
    }
    always {
      sh 'rm -f /var/jenkins_home/.jenkins_self_deploy || true'
    }
  }
}