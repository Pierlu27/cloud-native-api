pipeline {
    agent none

    options {
        skipDefaultCheckout(true)
    }

    environment {
        GCP_PROJECT_ID = 'project-c42baf60-7736-408b-9ff'
        ARTIFACT_REGISTRY_REGION = 'europe-west8'
        ARTIFACT_REGISTRY_REPOSITORY = 'cloud-native-api'
        DEVELOPMENT_IMAGE_NAME = 'cloud-native-api-dev'
    }

    stages {
        stage('Continuous Integration') {
            agent { label 'build-test' }

            stages {
                stage('Checkout') {
                    steps {
                        checkout scm
                    }
                }

                stage('Build') {
                    steps {
                        sh './gradlew clean assemble --no-daemon'
                    }
                }

                stage('Test') {
                    steps {
                        sh './gradlew test --no-daemon'
                    }

                    post {
                        always {
                            junit testResults: 'build/test-results/test/*.xml'
                        }
                    }
                }

                stage('Checkstyle') {
                    steps {
                        sh './gradlew checkstyleMain checkstyleTest --no-daemon'
                    }

                    post {
                        always {
                            recordIssues(
                                enabledForFailure: true,
                                tools: [checkStyle(pattern: 'build/reports/checkstyle/*.xml')]
                            )
                            archiveArtifacts(
                                artifacts: 'build/reports/checkstyle/**/*.html,build/reports/checkstyle/**/*.sarif',
                                allowEmptyArchive: true
                            )
                        }
                    }
                }

                stage('Runtime Dependency Check') {
                    steps {
                        withCredentials([
                            string(credentialsId: 'nvd-api-key', variable: 'NVD_API_KEY')
                        ]) {
                            sh './gradlew dependencyCheckAnalyze --no-daemon'
                        }
                    }

                    post {
                        always {
                            archiveArtifacts(
                                artifacts: 'build/reports/dependency-check-report.*',
                                allowEmptyArchive: true
                            )
                        }
                    }
                }

                stage('Build Dependency Check') {
                    steps {
                        sh '''
                            mkdir -p build/reports/build-dependencies
                            ./gradlew buildEnvironment --no-daemon --console=plain > build/reports/build-dependencies/gradle-build-environment.txt
                            cat build/reports/build-dependencies/gradle-build-environment.txt
                        '''

                        withCredentials([
                            string(credentialsId: 'nvd-api-key', variable: 'NVD_API_KEY')
                        ]) {
                            sh './gradlew dependencyCheckBuildEnvironment --no-daemon'
                        }
                    }

                    post {
                        always {
                            archiveArtifacts(
                                artifacts: 'build/reports/build-dependencies/**/*',
                                allowEmptyArchive: true
                            )
                        }
                    }
                }

                stage('Gitleaks') {
                    steps {
                        sh '''
                            mkdir -p build/reports/gitleaks
                            gitleaks git \
                                --config .gitleaks.toml \
                                --report-format json \
                                --report-path build/reports/gitleaks/gitleaks-report.json \
                                --redact \
                                --no-banner \
                                --no-color \
                                --verbose \
                                .
                        '''
                    }

                    post {
                        always {
                            archiveArtifacts(
                                artifacts: 'build/reports/gitleaks/gitleaks-report.json',
                                allowEmptyArchive: true
                            )
                        }
                    }
                }
            }
        }

        stage('Container Security & Publishing') {
            agent { label 'docker' }

            stages {
                stage('Container Checkout') {
                    steps {
                        checkout scm

                        script {
                            env.CONTAINER_COMMIT_SHA = sh(
                                script: 'git rev-parse HEAD',
                                returnStdout: true
                            ).trim()

                            if (!(env.CONTAINER_COMMIT_SHA ==~ /^[0-9a-f]{40}$/)) {
                                error "Expected a full Git commit SHA, got: ${env.CONTAINER_COMMIT_SHA}"
                            }

                            env.DEVELOPMENT_IMAGE_URI = "${env.ARTIFACT_REGISTRY_REGION}-docker.pkg.dev/" +
                                "${env.GCP_PROJECT_ID}/${env.ARTIFACT_REGISTRY_REPOSITORY}/" +
                                "${env.DEVELOPMENT_IMAGE_NAME}"
                        }
                    }
                }

                stage('Docker Build') {
                    steps {
                        sh '''
                            docker build \
                                --tag "${DEVELOPMENT_IMAGE_URI}:${CONTAINER_COMMIT_SHA}" \
                                .

                            docker image inspect \
                                --format 'Built image ID: {{.Id}}' \
                                "${DEVELOPMENT_IMAGE_URI}:${CONTAINER_COMMIT_SHA}"
                        '''
                    }
                }

                stage('Trivy Image Scan') {
                    steps {
                        sh '''
                            mkdir -p build/reports/trivy

                            trivy image \
                                --cache-dir "${TRIVY_CACHE_DIR}" \
                                --scanners vuln \
                                --severity HIGH,CRITICAL \
                                --format json \
                                --output build/reports/trivy/image-scan.json \
                                "${DEVELOPMENT_IMAGE_URI}:${CONTAINER_COMMIT_SHA}"

                            trivy convert \
                                --format table \
                                --output build/reports/trivy/image-scan.txt \
                                --exit-code 1 \
                                build/reports/trivy/image-scan.json
                        '''
                    }

                    post {
                        always {
                            archiveArtifacts(
                                artifacts: 'build/reports/trivy/image-scan.json,build/reports/trivy/image-scan.txt',
                                allowEmptyArchive: true
                            )
                        }
                    }
                }

                stage('Trivy IaC Scan') {
                    steps {
                        sh '''
                            mkdir -p build/reports/trivy

                            trivy config \
                                --cache-dir "${TRIVY_CACHE_DIR}" \
                                --tf-vars terraform/terraform.tfvars.example \
                                --severity HIGH,CRITICAL \
                                --format json \
                                --output build/reports/trivy/iac-scan.json \
                                terraform/

                            trivy convert \
                                --format table \
                                --output build/reports/trivy/iac-scan.txt \
                                --exit-code 1 \
                                build/reports/trivy/iac-scan.json
                        '''
                    }

                    post {
                        always {
                            archiveArtifacts(
                                artifacts: 'build/reports/trivy/iac-scan.json,build/reports/trivy/iac-scan.txt',
                                allowEmptyArchive: true
                            )
                        }
                    }
                }

                stage('Docker Push') {
                    when {
                        allOf {
                            branch 'develop'
                            not {
                                changeRequest()
                            }
                        }
                    }

                    steps {
                        withCredentials([
                            string(
                                credentialsId: 'artifact-registry-publisher-key-base64',
                                variable: 'ARTIFACT_REGISTRY_PUBLISHER_KEY_BASE64'
                            )
                        ]) {
                            sh '''
                                set -eu

                                registry_host="${ARTIFACT_REGISTRY_REGION}-docker.pkg.dev"
                                temporary_docker_config="$(mktemp -d /tmp/jenkins-docker-config.XXXXXX)"
                                export DOCKER_CONFIG="${temporary_docker_config}"

                                cleanup_docker_auth() {
                                    docker logout "${registry_host}" >/dev/null 2>&1 || true
                                    rm -f "${DOCKER_CONFIG}/config.json" || true
                                    rmdir "${DOCKER_CONFIG}" >/dev/null 2>&1 || true
                                }
                                trap cleanup_docker_auth EXIT

                                set +x
                                printf '%s' "${ARTIFACT_REGISTRY_PUBLISHER_KEY_BASE64}" | \
                                    docker login \
                                        --username _json_key_base64 \
                                        --password-stdin \
                                        "${registry_host}"
                                set -x

                                docker tag \
                                    "${DEVELOPMENT_IMAGE_URI}:${CONTAINER_COMMIT_SHA}" \
                                    "${DEVELOPMENT_IMAGE_URI}:latest"

                                docker push "${DEVELOPMENT_IMAGE_URI}:${CONTAINER_COMMIT_SHA}"
                                docker push "${DEVELOPMENT_IMAGE_URI}:latest"
                            '''
                        }
                    }
                }
            }
        }
    }
}
