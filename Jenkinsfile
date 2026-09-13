pipeline {
    agent none

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
    }

    parameters {
        booleanParam(
            name: 'FORCE_SMOKE_TEST_FAILURE',
            defaultValue: false,
            description: 'Fail after the real development candidate smoke tests to verify that traffic is not promoted.'
        )
    }

    environment {
        GCP_PROJECT_ID = 'project-c42baf60-7736-408b-9ff'
        ARTIFACT_REGISTRY_REGION = 'europe-west8'
        ARTIFACT_REGISTRY_REPOSITORY = 'cloud-native-api'
        DEVELOPMENT_IMAGE_NAME = 'cloud-native-api-dev'
        CLOUD_RUN_REGION = 'europe-west8'
        DEVELOPMENT_CLOUD_RUN_SERVICE = 'cloud-native-api-dev'
        DEVELOPMENT_SMOKE_READINESS_PATH = '/actuator/health/readiness'
        DEVELOPMENT_SMOKE_APPLICATION_PATH = '/api/jobs'
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

                stage('Prepare Development Delivery') {
                    when {
                        allOf {
                            branch 'develop'
                            not {
                                changeRequest()
                            }
                        }
                    }

                    steps {
                        script {
                            if (!(env.BUILD_NUMBER ==~ /^[0-9]+$/)) {
                                error "Expected a numeric Jenkins build number, got: ${env.BUILD_NUMBER}"
                            }

                            def shortSha = env.CONTAINER_COMMIT_SHA.take(8)
                            def revisionSuffix = "sha-${shortSha}-build-${env.BUILD_NUMBER}"
                            def revisionName = "${env.DEVELOPMENT_CLOUD_RUN_SERVICE}-${revisionSuffix}"
                            def candidateTag = "cand-${shortSha}-b${env.BUILD_NUMBER}"

                            if (!(revisionName ==~ /^[a-z][a-z0-9-]{0,61}[a-z0-9]$/)) {
                                error "Invalid Cloud Run revision name: ${revisionName}"
                            }

                            if (env.DEVELOPMENT_CLOUD_RUN_SERVICE.length() + candidateTag.length() > 46) {
                                error "Cloud Run service name and candidate tag exceed the combined 46-character limit"
                            }

                            env.DEVELOPMENT_CANDIDATE_IMAGE =
                                "${env.DEVELOPMENT_IMAGE_URI}:${env.CONTAINER_COMMIT_SHA}"
                            env.DEVELOPMENT_CANDIDATE_REVISION_SUFFIX = revisionSuffix
                            env.DEVELOPMENT_CANDIDATE_REVISION = revisionName
                            env.DEVELOPMENT_CANDIDATE_TAG = candidateTag

                            currentBuild.description =
                                "development | ${env.CONTAINER_COMMIT_SHA} | ${revisionName}"

                            echo "Development image: ${env.DEVELOPMENT_CANDIDATE_IMAGE}"
                            echo "Development revision: ${env.DEVELOPMENT_CANDIDATE_REVISION}"
                            echo "Jenkins build number: ${env.BUILD_NUMBER}"
                        }
                    }
                }

                stage('Authenticate Development Deployer') {
                    when {
                        allOf {
                            branch 'develop'
                            not {
                                changeRequest()
                            }
                        }
                    }

                    steps {
                        script {
                            env.CLOUDSDK_CONFIG = sh(
                                script: 'mktemp -d /tmp/jenkins-gcloud-config.XXXXXX',
                                returnStdout: true
                            ).trim()

                            if (!(env.CLOUDSDK_CONFIG ==~ /^\/tmp\/jenkins-gcloud-config\.[A-Za-z0-9]+$/)) {
                                error "Unexpected temporary gcloud configuration path"
                            }
                        }

                        withCredentials([
                            string(
                                credentialsId: 'cloud-run-dev-deployer-key-base64',
                                variable: 'CLOUD_RUN_DEV_DEPLOYER_KEY_BASE64'
                            )
                        ]) {
                            sh '''
                                set -eu
                                set +x

                                temporary_key_file="$(mktemp "${CLOUDSDK_CONFIG}/service-account-key.XXXXXX.json")"

                                cleanup_key_file() {
                                    rm -f "${temporary_key_file}"
                                }
                                trap cleanup_key_file EXIT HUP INT TERM

                                printf '%s' "${CLOUD_RUN_DEV_DEPLOYER_KEY_BASE64}" | \
                                    base64 --decode > "${temporary_key_file}"
                                chmod 600 "${temporary_key_file}"

                                credential_type="$(jq -r '.type // empty' "${temporary_key_file}")"
                                credential_account="$(jq -r '.client_email // empty' "${temporary_key_file}")"
                                expected_account="jenkins-cloud-run-dev-deployer@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

                                if [ "${credential_type}" != 'service_account' ]; then
                                    echo 'The Jenkins development deployer credential is not a service-account key.' >&2
                                    exit 1
                                fi

                                if [ "${credential_account}" != "${expected_account}" ]; then
                                    echo 'The Jenkins credential belongs to an unexpected service account.' >&2
                                    exit 1
                                fi

                                gcloud auth activate-service-account \
                                    "${credential_account}" \
                                    --key-file "${temporary_key_file}" \
                                    --project "${GCP_PROJECT_ID}" \
                                    --quiet

                                active_account="$(gcloud auth list \
                                    --filter='status:ACTIVE' \
                                    --format='value(account)')"

                                if [ "${active_account}" != "${expected_account}" ]; then
                                    echo 'gcloud did not activate the expected development deployer.' >&2
                                    exit 1
                                fi

                                echo "Authenticated development deployer: ${active_account}"
                            '''
                        }

                        script {
                            env.DEVELOPMENT_GCLOUD_AUTHENTICATED = 'true'
                        }
                    }
                }

                stage('Deploy Development Candidate') {
                    when {
                        allOf {
                            branch 'develop'
                            not {
                                changeRequest()
                            }
                        }
                    }

                    steps {
                        sh '''
                            set -eu

                            gcloud run deploy "${DEVELOPMENT_CLOUD_RUN_SERVICE}" \
                                --image "${DEVELOPMENT_CANDIDATE_IMAGE}" \
                                --revision-suffix "${DEVELOPMENT_CANDIDATE_REVISION_SUFFIX}" \
                                --tag "${DEVELOPMENT_CANDIDATE_TAG}" \
                                --no-traffic \
                                --project "${GCP_PROJECT_ID}" \
                                --region "${CLOUD_RUN_REGION}" \
                                --platform managed \
                                --quiet

                            deployed_revision="$(gcloud run revisions describe \
                                "${DEVELOPMENT_CANDIDATE_REVISION}" \
                                --project "${GCP_PROJECT_ID}" \
                                --region "${CLOUD_RUN_REGION}" \
                                --format='value(metadata.name)')"

                            if [ "${deployed_revision}" != "${DEVELOPMENT_CANDIDATE_REVISION}" ]; then
                                echo 'Cloud Run did not create the expected candidate revision.' >&2
                                exit 1
                            fi

                            candidate_traffic="$(
                                gcloud run services describe "${DEVELOPMENT_CLOUD_RUN_SERVICE}" \
                                    --project "${GCP_PROJECT_ID}" \
                                    --region "${CLOUD_RUN_REGION}" \
                                    --format=json \
                                | jq -r --arg revision "${DEVELOPMENT_CANDIDATE_REVISION}" \
                                    '[.status.traffic[]? | select(.revisionName == $revision) | (.percent // 0)] | add // 0'
                            )"

                            if [ "${candidate_traffic}" != '0' ]; then
                                echo "Candidate revision unexpectedly received ${candidate_traffic}% traffic." >&2
                                exit 1
                            fi

                            echo "Candidate revision deployed with ${candidate_traffic}% service traffic."
                        '''
                    }
                }

                stage('Resolve Development Candidate URL') {
                    when {
                        allOf {
                            branch 'develop'
                            not {
                                changeRequest()
                            }
                        }
                    }

                    steps {
                        script {
                            env.DEVELOPMENT_CANDIDATE_URL = sh(
                                script: '''
                                    set -eu

                                    service_status="$(gcloud run services describe "${DEVELOPMENT_CLOUD_RUN_SERVICE}" \
                                        --project "${GCP_PROJECT_ID}" \
                                        --region "${CLOUD_RUN_REGION}" \
                                        --format=json)"

                                    printf '%s' "${service_status}" | jq -r \
                                        --arg tag "${DEVELOPMENT_CANDIDATE_TAG}" \
                                        --arg revision "${DEVELOPMENT_CANDIDATE_REVISION}" \
                                        '[.status.traffic[]? | select(.tag == $tag and .revisionName == $revision) | (.url // .uri)][0] // empty'
                                ''',
                                returnStdout: true
                            ).trim()

                            def expectedUrlPrefix = "https://${env.DEVELOPMENT_CANDIDATE_TAG}---"
                            if (!env.DEVELOPMENT_CANDIDATE_URL.startsWith(expectedUrlPrefix) ||
                                !env.DEVELOPMENT_CANDIDATE_URL.endsWith('.a.run.app')) {
                                error "Cloud Run did not return the expected tagged candidate URL"
                            }

                            echo "Development candidate URL: ${env.DEVELOPMENT_CANDIDATE_URL}"
                        }
                    }
                }

                stage('Smoke Test Development Candidate') {
                    when {
                        allOf {
                            branch 'develop'
                            not {
                                changeRequest()
                            }
                        }
                    }

                    steps {
                        sh '''
                            set -eu

                            echo 'Checking the candidate readiness endpoint...'
                            curl --fail --silent --show-error \
                                --retry 5 \
                                --retry-all-errors \
                                --retry-delay 10 \
                                --connect-timeout 5 \
                                --max-time 20 \
                                --output /dev/null \
                                "${DEVELOPMENT_CANDIDATE_URL}${DEVELOPMENT_SMOKE_READINESS_PATH}"
                            echo 'Candidate readiness smoke test passed.'

                            echo 'Checking the candidate application endpoint...'
                            curl --fail --silent --show-error \
                                --retry 5 \
                                --retry-all-errors \
                                --retry-delay 10 \
                                --connect-timeout 5 \
                                --max-time 20 \
                                --output /dev/null \
                                "${DEVELOPMENT_CANDIDATE_URL}${DEVELOPMENT_SMOKE_APPLICATION_PATH}"
                            echo 'Candidate application smoke test passed.'

                            if [ "${FORCE_SMOKE_TEST_FAILURE}" = 'true' ]; then
                                echo 'Controlled smoke-test failure requested; candidate traffic will not be promoted.' >&2
                                exit 1
                            fi
                        '''
                    }
                }

                stage('Promote Development Candidate') {
                    when {
                        allOf {
                            branch 'develop'
                            not {
                                changeRequest()
                            }
                        }
                    }

                    steps {
                        sh '''
                            set -eu

                            gcloud run services update-traffic \
                                "${DEVELOPMENT_CLOUD_RUN_SERVICE}" \
                                --to-revisions "${DEVELOPMENT_CANDIDATE_REVISION}=100" \
                                --project "${GCP_PROJECT_ID}" \
                                --region "${CLOUD_RUN_REGION}" \
                                --platform managed \
                                --quiet

                            echo "Promoted tested revision ${DEVELOPMENT_CANDIDATE_REVISION} to 100% development traffic."
                        '''
                    }
                }

                stage('Verify Development Traffic') {
                    when {
                        allOf {
                            branch 'develop'
                            not {
                                changeRequest()
                            }
                        }
                    }

                    steps {
                        sh '''
                            set -eu

                            attempt=1
                            max_attempts=6

                            while [ "${attempt}" -le "${max_attempts}" ]; do
                                service_status="$(gcloud run services describe \
                                    "${DEVELOPMENT_CLOUD_RUN_SERVICE}" \
                                    --project "${GCP_PROJECT_ID}" \
                                    --region "${CLOUD_RUN_REGION}" \
                                    --format=json)"

                                promoted_traffic="$(
                                    printf '%s' "${service_status}" \
                                    | jq -r --arg revision "${DEVELOPMENT_CANDIDATE_REVISION}" \
                                        '[.status.traffic[]? | select(.revisionName == $revision) | (.percent // 0)] | add // 0'
                                )"

                                if [ "${promoted_traffic}" = '100' ]; then
                                    echo "Verified revision ${DEVELOPMENT_CANDIDATE_REVISION} at 100% development traffic."
                                    exit 0
                                fi

                                echo "Attempt ${attempt}/${max_attempts}: candidate currently reports ${promoted_traffic}% traffic."

                                if [ "${attempt}" -lt "${max_attempts}" ]; then
                                    sleep 5
                                fi
                                attempt=$((attempt + 1))
                            done

                            echo "Revision ${DEVELOPMENT_CANDIDATE_REVISION} was not observed at 100% traffic." >&2
                            exit 1
                        '''
                    }
                }
            }

            post {
                always {
                    script {
                        if (env.BRANCH_NAME == 'develop' && !env.CHANGE_ID) {
                            sh '''
                                set -u

                                cleanup_failed=0

                                if [ "${DEVELOPMENT_GCLOUD_AUTHENTICATED:-false}" = 'true' ] && \
                                   [ -n "${DEVELOPMENT_CANDIDATE_TAG:-}" ]; then
                                    if service_status="$(gcloud run services describe \
                                        "${DEVELOPMENT_CLOUD_RUN_SERVICE}" \
                                        --project "${GCP_PROJECT_ID}" \
                                        --region "${CLOUD_RUN_REGION}" \
                                        --format=json)"; then
                                        tag_present="$(
                                            printf '%s' "${service_status}" \
                                            | jq -r --arg tag "${DEVELOPMENT_CANDIDATE_TAG}" \
                                                'any(.status.traffic[]?; .tag == $tag)'
                                        )"

                                        if [ "${tag_present}" = 'true' ]; then
                                            if gcloud run services update-traffic \
                                                "${DEVELOPMENT_CLOUD_RUN_SERVICE}" \
                                                --remove-tags "${DEVELOPMENT_CANDIDATE_TAG}" \
                                                --project "${GCP_PROJECT_ID}" \
                                                --region "${CLOUD_RUN_REGION}" \
                                                --platform managed \
                                                --quiet; then
                                                echo "Removed temporary candidate tag ${DEVELOPMENT_CANDIDATE_TAG}."
                                            else
                                                echo "Failed to remove temporary candidate tag ${DEVELOPMENT_CANDIDATE_TAG}." >&2
                                                cleanup_failed=1
                                            fi
                                        else
                                            echo 'No temporary candidate tag needs removal.'
                                        fi
                                    else
                                        echo 'Could not inspect Cloud Run while cleaning the candidate tag.' >&2
                                        cleanup_failed=1
                                    fi

                                    gcloud auth revoke --all --quiet >/dev/null 2>&1 || true
                                fi

                                if [ -n "${CLOUDSDK_CONFIG:-}" ]; then
                                    config_parent="$(dirname -- "${CLOUDSDK_CONFIG}")"
                                    config_name="$(basename -- "${CLOUDSDK_CONFIG}")"

                                    case "${config_name}" in
                                        jenkins-gcloud-config.*)
                                            if [ "${config_parent}" = '/tmp' ]; then
                                                rm -rf -- "${CLOUDSDK_CONFIG}"
                                                echo 'Removed temporary gcloud configuration.'
                                            else
                                                echo 'Refusing to remove gcloud configuration outside /tmp.' >&2
                                                cleanup_failed=1
                                            fi
                                            ;;
                                        *)
                                            echo 'Refusing to remove an unexpected gcloud configuration path.' >&2
                                            cleanup_failed=1
                                            ;;
                                    esac
                                fi

                                exit "${cleanup_failed}"
                            '''
                        }
                    }
                }
            }
        }
    }
}
