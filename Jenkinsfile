
def secrets = [
    [path: params.VAULT_PATH_SVC_ACCOUNT_EPHEMERAL, secretValues: [
        [envVar: 'OC_LOGIN_TOKEN_DEV', vaultKey: 'oc-login-token-dev'],
        [envVar: 'OC_LOGIN_SERVER_DEV', vaultKey: 'oc-login-server-dev'],
        [envVar: 'OC_LOGIN_TOKEN', vaultKey: 'oc-login-token'],
        [envVar: 'OC_LOGIN_SERVER', vaultKey: 'oc-login-server']]],
    [path: params.VAULT_PATH_QUAY_PUSH, secretValues: [
        [envVar: 'QUAY_USER', vaultKey: 'user'],
        [envVar: 'QUAY_TOKEN', vaultKey: 'token']]],
    [path: params.VAULT_PATH_INSIGHTSDROID_GITHUB, secretValues: [
        [envVar: 'GITHUB_TOKEN', vaultKey: 'token'],
        [envVar: 'GITHUB_API_URL', vaultKey: 'mirror_url']]],
    [path: params.VAULT_PATH_RHR_PULL, secretValues: [
        [envVar: 'RH_REGISTRY_USER', vaultKey: 'user'],
        [envVar: 'RH_REGISTRY_TOKEN', vaultKey: 'token']]]
]

def configuration = [vaultUrl: params.VAULT_ADDRESS, vaultCredentialId: params.VAULT_CREDS_ID]

pipeline {
    agent { label 'rhel8' }
    options {
        timestamps()
        parallelsAlwaysFailFast()
    }
    environment {
        COMPONENT="frontend-common-test"
        IMAGE="quay.io/cloudservices/$COMPONENT"
        TEST_REPOSITORY='https://github.com/RedHatInsights/frontend-common-test.git'
    }

    stages {
        stage('Clone test repository') { 
            steps {
                withVault([configuration: configuration, vaultSecrets: secrets]) {
                    script {
                        git branch: 'main',
                            url: "${env.TEST_RESPOSITORY}"
                    }
                }
            }
        }
        stage('Run Tests') {
            steps {
                withVault([configuration: configuration, vaultSecrets: secrets]) {
                    dir('frontend-common-test') {
                        sh 'bash -x pr-check.sh'
                    }
                }
            }
        }
    }
}
