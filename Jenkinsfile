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
}