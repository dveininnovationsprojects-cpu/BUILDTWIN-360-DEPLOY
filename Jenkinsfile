// BuildTwin 360 - staging deploy pipeline (Windows agent with Docker Desktop)
//
// Jenkins prerequisites:
//   * Docker available to the Jenkins service account (docker compose v2)
//   * Credentials (Kind: Secret text):
//       buildtwin-staging-db-password   -> PostgreSQL password
//       buildtwin-staging-jwt-secret    -> JWT signing secret
//       buildtwin-staging-admin-password -> password for the seeded "admin" user (replaces Admin@123)
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
        booleanParam(name: 'RUN_SECURITY_SCANS', defaultValue: true, description: 'Run Trivy image scans and ZAP scans after deploy (report only)')
        booleanParam(name: 'RUN_LOAD_TEST', defaultValue: true, description: 'Run the k6 load test after deploy')
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
                // Copy a file unless the app repo tracks its own version. "if not exist" is not enough:
                // the workspace is reused, so a copy from an earlier build would never be refreshed.
                bat '''
                    git -C backend ls-files --error-unmatch Dockerfile >nul 2>&1 || copy /Y docker\\backend\\Dockerfile backend\\Dockerfile
                    git -C backend ls-files --error-unmatch .dockerignore >nul 2>&1 || copy /Y docker\\backend\\.dockerignore backend\\.dockerignore
                    git -C frontend ls-files --error-unmatch Dockerfile >nul 2>&1 || copy /Y docker\\frontend\\Dockerfile frontend\\Dockerfile
                    git -C frontend ls-files --error-unmatch .dockerignore >nul 2>&1 || copy /Y docker\\frontend\\.dockerignore frontend\\.dockerignore
                    git -C frontend ls-files --error-unmatch nginx.conf >nul 2>&1 || copy /Y docker\\frontend\\nginx.conf frontend\\nginx.conf
                    git -C frontend ls-files --error-unmatch security-headers.inc >nul 2>&1 || copy /Y docker\\frontend\\security-headers.inc frontend\\security-headers.inc
                    exit /b 0
                '''
            }
        }

        stage('Deploy to Staging') {
            steps {
                withCredentials([
                    string(credentialsId: 'buildtwin-staging-db-password', variable: 'POSTGRES_PASSWORD'),
                    string(credentialsId: 'buildtwin-staging-jwt-secret', variable: 'JWT_SECRET_KEY'),
                    string(credentialsId: 'buildtwin-staging-admin-password', variable: 'APP_SEED_ADMIN_PASSWORD')
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

        stage('API Smoke Tests (Newman)') {
            steps {
                // Runs inside the compose network so it reaches the backend directly
                withCredentials([string(credentialsId: 'buildtwin-staging-admin-password', variable: 'ADMIN_PASSWORD')]) {
                    bat '''
                        if exist postman\\newman-results.xml del postman\\newman-results.xml
                        docker run --rm --network buildtwin-staging_default -v "%WORKSPACE%\\postman:/etc/newman" postman/newman:alpine run staging-smoke.postman_collection.json --env-var base_url=http://backend:8080 --env-var admin_password=%ADMIN_PASSWORD% --reporters cli,junit --reporter-junit-export /etc/newman/newman-results.xml
                    '''
                }
            }
        }

        // The next three stages are report only: a scanner problem marks the stage UNSTABLE
        // but never blocks the deploy. Reports are archived from ./reports.
        stage('Image Scan (Trivy)') {
            when { expression { params.RUN_SECURITY_SCANS } }
            steps {
                catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                    bat '''
                        if not exist reports mkdir reports
                        docker run --rm -v //var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache aquasec/trivy:latest image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed buildtwin-staging-frontend > reports\\trivy-frontend.txt
                        docker run --rm -v //var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache aquasec/trivy:latest image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed buildtwin-staging-backend > reports\\trivy-backend.txt
                        type reports\\trivy-frontend.txt
                        type reports\\trivy-backend.txt
                    '''
                }
            }
        }

        stage('Web Scan (ZAP)') {
            when { expression { params.RUN_SECURITY_SCANS } }
            options { timeout(time: 15, unit: 'MINUTES') }
            steps {
                catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                    // -I: findings are reported but do not make the scan command fail
                    bat '''
                        if not exist reports mkdir reports
                        docker run --rm --network buildtwin-staging_default -v "%WORKSPACE%\\reports:/zap/wrk:rw" ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t http://frontend:80 -r zap-baseline.html -I
                        docker run --rm --network buildtwin-staging_default -v "%WORKSPACE%\\reports:/zap/wrk:rw" ghcr.io/zaproxy/zaproxy:stable zap-api-scan.py -t http://backend:8080/v3/api-docs -f openapi -r zap-api.html -I -P 8091 -T 3
                    '''
                }
            }
        }

        stage('Load Test (k6)') {
            when { expression { params.RUN_LOAD_TEST } }
            steps {
                catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                    withCredentials([string(credentialsId: 'buildtwin-staging-admin-password', variable: 'ADMIN_PASSWORD')]) {
                        bat '''
                            if not exist reports mkdir reports
                            docker run --rm --network buildtwin-staging_default -v "%WORKSPACE%\\k6:/scripts" -v "%WORKSPACE%\\reports:/out" grafana/k6:latest run -e BASE_URL=http://backend:8080 -e ADMIN_USER=admin -e ADMIN_PASSWORD=%ADMIN_PASSWORD% --summary-export=/out/k6-summary.json /scripts/smoke-load.js
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            junit allowEmptyResults: true, testResults: 'postman/newman-results.xml'
            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
        }
        success {
            echo "Staging deployed: app http://localhost:${env.FRONTEND_PORT}  Swagger http://localhost:${env.BACKEND_PORT}/swagger-ui.html"
        }
        failure {
            withEnv(['POSTGRES_PASSWORD=unused', 'JWT_SECRET_KEY=unused', 'APP_SEED_ADMIN_PASSWORD=unused']) {
                bat 'docker compose ps -a'
                bat 'docker compose logs --tail 80'
            }
        }
    }
}
