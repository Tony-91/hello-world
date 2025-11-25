#!/bin/bash

# Wait for Jenkins to be up and running
echo "Waiting for Jenkins to start..."
while ! curl -s http://localhost:8080 > /dev/null; do
  sleep 5
done

# Get the initial admin password
JENKINS_PASSWORD=$(docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null)

if [ -z "$JENKINS_PASSWORD" ]; then
  echo "Jenkins already initialized"
  exit 0
fi

# Install required plugins
echo "Installing Jenkins plugins..."
docker exec jenkins bash -c "\
  jenkins-plugin-cli --plugins \
  docker-workflow \
  kubernetes \
  pipeline-utility-steps \
  git \
  blueocean \
  configuration-as-code \
  credentials-binding \
  ssh-agent \
  ws-cleanup \
  workflow-aggregator"

# Restart Jenkins to apply changes
echo "Restarting Jenkins..."
docker restart jenkins

echo "Jenkins setup complete!"
echo "Initial Admin Password: $JENKINS_PASSWORD"
echo "Access Jenkins at http://localhost:8080"
