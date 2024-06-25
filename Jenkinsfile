pipeline {
    agent { label 'rhel8' }
    options {
        timestamps()
    }
    stages {
        stage('Dummy stage') { 
            steps {
                sh "echo 'OK'"
            }
        }
    }
}
