// Load the shared library from our pipeline framework
// Load the shared library from our pipeline framework
@Library('green-pipes') _

pipeline {
    agent any
    
    environment {
        // Base workspace path
        WORKSPACE_PATH = "${env.WORKSPACE}"
        
        // Docker settings
        DOCKER_HOST = 'unix:///var/run/docker.sock'
        DOCKER_TLS_CERTDIR = ''
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }
    agent any
    
    environment {
        // Base workspace path
        WORKSPACE_PATH = "${env.WORKSPACE}"
        
        // Docker settings
        DOCKER_HOST = 'unix:///var/run/docker.sock'
        DOCKER_TLS_CERTDIR = ''
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
    
    stages {
        stage('Initialize') {
            steps {
                script {
                    // Print workspace information
                    echo "Workspace: ${WORKSPACE}"
                    echo "Current directory: ${pwd()}"
                    sh 'ls -la'
                    
                    // Load configuration
                    if (!fileExists('pipeline-config.yaml')) {
                        error "pipeline-config.yaml not found in ${pwd()}"
                    }
                    
                    // Read and parse the configuration
                    def config = readYaml file: 'pipeline-config.yaml'
                    
                    // Set global environment variables
                    env.APP_NAME = config.application.name
                    env.APP_VERSION = config.application.version
                    env.APP_PORT = config.kubernetes.service_port
                    
                    // Set Docker and Kubernetes variables
                    env.DOCKER_REGISTRY = config.docker.registry
                    env.DOCKER_NAMESPACE = config.docker.namespace
                    env.DOCKER_IMAGE = "${env.DOCKER_REGISTRY}/${env.DOCKER_NAMESPACE}/${env.APP_NAME}:${env.BUILD_NUMBER}"
                    env.KUBE_NAMESPACE = "${env.APP_NAME}-${config.deployment.environment}"
                    
                    echo "Loaded configuration for ${env.APP_NAME} v${env.APP_VERSION}"
                }
            }
        }
        
        stage('Checkout') {
            steps {
                checkout scm
                echo 'Code checked out successfully'
            }
        }
        
        stage('Build') {
            agent {
                docker {
                    image 'maven:3.8.4-jdk-11'
                    args '-v $HOME/.m2:/root/.m2'
                    reuseNode true
                }
            }
            steps {
                script {
                    echo "Building ${env.APP_NAME} v${env.APP_VERSION}"
                    echo "Docker Image: ${env.DOCKER_IMAGE}"
                    
                    // Build the application
                    sh 'mvn --version'
                    sh 'mvn clean package -DskipTests'
                    
                    // Build Docker image using the host's Docker daemon
                    withDockerContainer(args: '-v /var/run/docker.sock:/var/run/docker.sock', image: 'docker:20.10.16-dind') {
                        sh """
                            docker build \
                                -t ${env.DOCKER_IMAGE} \
                                --build-arg JAR_FILE=target/*.jar \
                                .
                        """
                    }
                }
            }
        }
        
        stage('Test') {
            agent {
                docker {
                    image 'maven:3.8.4-jdk-11'
                    args '-v $HOME/.m2:/root/.m2'
                    reuseNode true
                }
            }
            steps {
                script {
                    echo "Running tests..."
                    sh 'mvn test'
                    
                    // Run integration tests if any
                    if (fileExists('src/test/integration')) {
                        sh 'mvn verify -Pintegration-tests'
                    }
                    
                    // Run container tests
                    withDockerContainer(args: '-v /var/run/docker.sock:/var/run/docker.sock', image: 'docker:20.10.16-dind') {
                        sh """
                            echo 'Running container tests...'
                            docker run --rm ${env.DOCKER_IMAGE} --version
                        """
                    }
                }
            }
        }
        
        stage('Deploy') {
            when {
                expression { 
                    env.BRANCH_NAME == 'main' || 
                    env.BRANCH_NAME == 'master' || 
                    env.BRANCH_NAME == 'develop' 
                }
            }
            steps {
                script {
                    echo "Deploying ${env.APP_NAME} to ${env.KUBE_NAMESPACE}"
                    
                    // Push Docker image
                    withCredentials([usernamePassword(
                        credentialsId: 'docker-hub-credentials',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh """
                            echo "${DOCKER_PASS}" | docker login -u "${DOCKER_USER}" --password-stdin
                            docker push ${env.DOCKER_IMAGE}
                        """
                    }
                    
                    // Deploy to Kubernetes
                    sh """
                        # Ensure namespace exists
                        kubectl create namespace ${env.KUBE_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                        
                        # Deploy application
                        kubectl apply -f kubernetes/ -n ${env.KUBE_NAMESPACE}
                        
                        # Wait for deployment to complete
                        kubectl rollout status deployment/${env.APP_NAME} -n ${env.KUBE_NAMESPACE}
                    """
                }
            }
        }
    }
    
    post {
        success {
            echo "Pipeline completed successfully!"
            // Add success notifications here (e.g., Slack, email)
        }
        failure {
            echo "Pipeline failed!"
            // Add failure notifications here
        }
        always {
            echo "Cleaning up..."
            // Add cleanup steps here
            sh 'docker logout'
        }
    }
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
