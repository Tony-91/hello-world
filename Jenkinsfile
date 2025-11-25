// Load the shared library from our pipeline framework
@Library('green-pipes') _

// Load pipeline configuration
def config = readYaml file: "${env.WORKSPACE}/pipeline-config.yaml"

// Set environment variables
env.APP_NAME = config.application.name
env.APP_VERSION = config.application.version
env.APP_PORT = config.kubernetes.service_port

// Define the pipeline
pipeline {
    agent any
    
    environment {
        // Docker configuration
        DOCKER_REGISTRY = config.docker.registry
        DOCKER_NAMESPACE = config.docker.namespace
        DOCKER_IMAGE = "${DOCKER_REGISTRY}/${DOCKER_NAMESPACE}/${APP_NAME}:${BUILD_NUMBER}"
        
        // Kubernetes configuration
        KUBE_NAMESPACE = "${APP_NAME}-${config.deployment.environment}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    // Verify pipeline configuration
                    if (!fileExists('pipeline-config.yaml')) {
                        error 'pipeline-config.yaml not found!'
                    }
                }
            }
        }

        stage('Build') {
            steps {
                script {
                    // Use the buildStages from our framework
                    buildStages.executeBuild('java')
                }
            }
        }

        stage('Test') {
            steps {
                script {
                    // Run tests
                    buildStages.executeTests('java')
                }
            }
        }

        stage('Build Docker Image') {
            when {
                expression { config.deployment.type == 'container' }
            }
            steps {
                script {
                    // Build Docker image using the template from our framework
                    sh """
                        cp ${WORKSPACE}/../Green_Pipes/docker/templates/java.Dockerfile .
                        docker build \
                            --build-arg BASE_IMAGE=${config.docker.base_image} \
                            -t ${DOCKER_IMAGE} \
                            -f java.Dockerfile \
                            .
                    """
                }
            }
        }

        stage('Push to Registry') {
            when {
                expression { config.deployment.type == 'container' }
            }
            steps {
                script {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'docker-registry-credentials',
                            usernameVariable: 'DOCKER_USER',
                            passwordVariable: 'DOCKER_PASS'
                        )
                    ]) {
                        sh "echo \"${DOCKER_PASS}\" | docker login -u \"${DOCKER_USER}\" --password-stdin ${DOCKER_REGISTRY}"
                        sh "docker push ${DOCKER_IMAGE}"
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            when {
                expression { config.deployment.target == 'kubernetes' }
            }
            steps {
                script {
                    // Create namespace if it doesn't exist
                    sh """
                        if ! kubectl get namespace ${KUBE_NAMESPACE} >/dev/null 2>&1; then
                            kubectl create namespace ${KUBE_NAMESPACE}
                        fi
                    """
                    
                    // Deploy using the deployment template
                    sh """
                        # Create a temporary directory for manifests
                        mkdir -p k8s-temp
                        
                        # Process and apply the deployment
                        sed -e "s/\$\{APP_NAME\}/${APP_NAME}/g" \
                            -e "s/\$\{DOCKER_IMAGE\}/${DOCKER_IMAGE//\//\\/}/g" \
                            -e "s/\$\{REPLICAS\}/${config.deployment.replicas}/g" \
                            -e "s/\$\{SERVICE_PORT\}/${config.kubernetes.service_port}/g" \
                            -e "s/\$\{TARGET_PORT\}/${config.kubernetes.target_port}/g" \
                            -e "s/\$\{RESOURCES_REQUESTS_CPU\}/${config.deployment.resources.requests.cpu}/g" \
                            -e "s/\$\{RESOURCES_REQUESTS_MEMORY\}/${config.deployment.resources.requests.memory}/g" \
                            -e "s/\$\{RESOURCES_LIMITS_CPU\}/${config.deployment.resources.limits.cpu}/g" \
                            -e "s/\$\{RESOURCES_LIMITS_MEMORY\}/${config.deployment.resources.limits.memory}/g" \
                            ${WORKSPACE}/../Green_Pipes/kubernetes/templates/deployment.yaml > k8s-temp/deployment.yaml
                        
                        # Apply the deployment
                        kubectl -n ${KUBE_NAMESPACE} apply -f k8s-temp/deployment.yaml
                        
                        # Cleanup
                        rm -rf k8s-temp
                    """
                    
                    // Wait for deployment to be ready
                    sh "kubectl -n ${KUBE_NAMESPACE} rollout status deployment/${APP_NAME} --timeout=300s"
                }
            }
        }
    }
    
    post {
        success {
            script {
                // Get the service URL
                def serviceUrl = ""
                if (config.deployment.target == 'kubernetes') {
                    if (config.kubernetes.service_type == 'LoadBalancer') {
                        serviceUrl = sh(script: "kubectl -n ${KUBE_NAMESPACE} get svc ${APP_NAME} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'", returnStdout: true).trim()
                        if (!serviceUrl) {
                            serviceUrl = sh(script: "kubectl -n ${KUBE_NAMESPACE} get svc ${APP_NAME} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()
                        }
                        if (serviceUrl) {
                            serviceUrl = "http://${serviceUrl}:${config.kubernetes.service_port}"
                        }
                    } else if (config.kubernetes.service_type == 'NodePort') {
                        def nodePort = sh(script: "kubectl -n ${KUBE_NAMESPACE} get svc ${APP_NAME} -o jsonpath='{.spec.ports[0].nodePort}'", returnStdout: true).trim()
                        def nodeIp = sh(script: "kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=='InternalIP')].address}'", returnStdout: true).trim()
                        if (nodePort && nodeIp) {
                            serviceUrl = "http://${nodeIp}:${nodePort}"
                        }
                    }
                }
                
                // Send notification
                if (serviceUrl) {
                    echo "Deployment successful! Application is available at: ${serviceUrl}"
                    // You can add Slack/Email notification here using the config.notifications settings
                } else {
                    echo "Deployment successful! Service URL not available (check service type and cluster configuration)."
                }
            }
        }
        
        failure {
            echo "Pipeline failed! Check the logs for more information."
            // Add failure notification here
        }
        
        always {
            // Clean up workspace
            cleanWs()
        }
    }
}
