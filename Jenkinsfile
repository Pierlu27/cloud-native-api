pipeline {
    agent { label 'build-test' }

    options {
        skipDefaultCheckout(true)
    }

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
