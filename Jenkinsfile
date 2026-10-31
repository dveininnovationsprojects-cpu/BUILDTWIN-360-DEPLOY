// BuildTwin 360 - staging deploy pipeline (Windows agent with Docker Desktop)
//
// Jenkins prerequisites:
//   * Docker available to the Jenkins service account (docker compose v2)
//   * Credentials (Kind: Secret text):
//       buildtwin-staging-db-password   -> PostgreSQL password
//       buildtwin-staging-jwt-secret    -> JWT signing secret
//
// The app repos are checked out into ./backend and ./frontend. The Dockerfiles in ./docker are
// copied in only when an app repo does not already have its own.

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    parameters {
        string(name: 'BACKEND_BRANCH', defaultValue: 'main2', description: 'Backend branch to deploy')
        string(name: 'FRONTEND_BRANCH', defaultValue: 'main2', description: 'Frontend branch to deploy')
    }

    environment {
        BACKEND_REPO  = 'https://github.com/dveininnovationsprojects-cpu/BUILDTWIN-360-BACKEND.git'
        FRONTEND_REPO = 'https://github.com/dveininnovationsprojects-cpu/BUILDTWIN-360-FRONTEND.git'
        BACKEND_PORT  = '8082'
        FRONTEND_PORT = '8089'
    }

    stages {
        stage('Checkout Deploy Config') {
            steps {
                checkout scm
            }
        }

        stage('Check Docker') {
            steps {
                bat 'docker version --format "{{.Server.Version}}"'
                bat 'docker compose version'
            }
        }

        stage('Checkout Applications') {
            steps {
                dir('backend') {
                    git url: env.BACKEND_REPO, branch: params.BACKEND_BRANCH
                }
                dir('frontend') {
                    git url: env.FRONTEND_REPO, branch: params.FRONTEND_BRANCH
                }
            }
        }

        stage('Add Docker Files') {
            steps {
                bat '''
                    if not exist backend\\Dockerfile copy /Y docker\\backend\\Dockerfile backend\\Dockerfile
                    if not exist backend\\.dockerignore copy /Y docker\\backend\\.dockerignore backend\\.dockerignore
                    if not exist frontend\\Dockerfile copy /Y docker\\frontend\\Dockerfile frontend\\Dockerfile
                    if not exist frontend\\.dockerignore copy /Y docker\\frontend\\.dockerignore frontend\\.dockerignore
                    if not exist frontend\\nginx.conf copy /Y docker\\frontend\\nginx.conf frontend\\nginx.conf
                    exit /b 0
                '''
            }
        }

        stage('Deploy to Staging') {
            steps {
                withCredentials([
                    string(credentialsId: 'buildtwin-staging-db-password', variable: 'POSTGRES_PASSWORD'),
                    string(credentialsId: 'buildtwin-staging-jwt-secret', variable: 'JWT_SECRET_KEY')
                ]) {
                    bat 'docker compose up -d --build --remove-orphans'
                }
            }
        }

        stage('Smoke Test') {
            steps {
                bat 'curl --fail --silent --show-error --retry 20 --retry-delay 5 --retry-connrefused --retry-all-errors -o NUL http://localhost:%BACKEND_PORT%/v3/api-docs'
                bat 'curl --fail --silent --show-error --retry 10 --retry-delay 3 --retry-connrefused --retry-all-errors -o NUL http://localhost:%FRONTEND_PORT%/'
                script {
                    // Without a login token the API must answer 401 through the nginx proxy
                    def code = bat(returnStdout: true,
                            script: '@curl --silent -o NUL -w "%%{http_code}" http://localhost:%FRONTEND_PORT%/api/v1/projects').trim()
                    if (code != '401') {
                        error "Expected 401 from /api/v1/projects through nginx, got ${code}"
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Staging deployed: app http://localhost:${env.FRONTEND_PORT}  Swagger http://localhost:${env.BACKEND_PORT}/swagger-ui.html"
        }
        failure {
            withEnv(['POSTGRES_PASSWORD=unused', 'JWT_SECRET_KEY=unused']) {
                bat 'docker compose ps -a'
                bat 'docker compose logs --tail 80'
            }
        }
    }
}
