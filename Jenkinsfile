pipeline {
    // Phase 14 only proves Multibranch discovery and agent routing. Build and
    // delivery stages remain intentionally deferred to the following phase.
    agent { label 'build-test' }

    stages {
        stage('Multibranch discovery') {
            steps {
                echo "Running ${env.JOB_NAME} for ${env.BRANCH_NAME}"
            }
        }
    }
}
