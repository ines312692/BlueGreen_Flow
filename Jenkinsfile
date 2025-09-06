pipeline {
  agent any

  environment {
    REGISTRY        = 'docker.io/inestmimi123'
    APP_NAME        = 'blue-green-app'
    IMAGE           = "${env.REGISTRY}/${env.APP_NAME}:${env.BUILD_NUMBER}"
    GITOPS_REPO_SSH = 'https://github.com/ines312692/BlueGreen-GitOps.git'
    GITOPS_BRANCH   = 'env/prod'
    GIT_USER_NAME   = 'gitops-bot'
    GIT_USER_EMAIL  = 'gitops-bot@example.com'
    HEALTH_URL      = 'https://app.example.com/health'
    NAMESPACE       = 'blue-green-demo'
  }

  options { timestamps() }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build') {
      steps {
        sh '''
          cd app
          npm ci
          echo "Pas de tests pour l’instant"
        '''
      }
    }

    stage('Build & Push Image') {
      environment { DOCKER_CREDENTIALS = credentials('docker-registry') }
      steps {
        sh '''
          docker login -u "$DOCKER_CREDENTIALS_USR" -p "$DOCKER_CREDENTIALS_PSW" ${REGISTRY%/*}
          docker build -t "$IMAGE" app
          docker push "$IMAGE"
        '''
      }
    }

    stage('Update GitOps (Deploy GREEN)') {
      environment { GIT_SSH = credentials('gitops-bot') }
      steps {
        sh '''
          set -e
          rm -rf gitops && git clone -b "$GITOPS_BRANCH" "$GITOPS_REPO_SSH" gitops
          cd gitops
          git config user.name "$GIT_USER_NAME"
          git config user.email "$GIT_USER_EMAIL"

          # Met à jour l'image et la version dans le déploiement GREEN
          yq -i '.spec.template.spec.containers[0].image = "'$IMAGE'"' environments/prod/deployment-green.yaml
          yq -i '(.spec.template.spec.containers[0].env[] | select(.name == "APP_VERSION") | .value) = "'$BUILD_NUMBER'"' environments/prod/deployment-green.yaml

          git add environments/prod/deployment-green.yaml
          git commit -m "ci: deploy green image $IMAGE"
          git push origin "$GITOPS_BRANCH"
        '''
      }
    }

    stage('Wait GREEN healthy') {
      steps {
        sh '''
          for i in $(seq 1 20); do
            if curl -fsS "$HEALTH_URL" >/dev/null; then
              echo "Green OK"
              exit 0
            fi
            echo "Attente de la santé GREEN..."
            sleep 10
          done
          echo "Green pas sain"
          exit 1
        '''
      }
    }

    stage('Switch Traffic -> GREEN') {
      environment { GIT_SSH = credentials('gitops-bot') }
      steps {
        sh '''
          cd gitops || (rm -rf gitops && git clone -b "$GITOPS_BRANCH" "$GITOPS_REPO_SSH" gitops && cd gitops)
          yq -i '(.spec.selector.color) = "green"' environments/prod/service.yaml
          git add environments/prod/service.yaml
          git commit -m "ci: switch traffic to green"
          git push origin "$GITOPS_BRANCH"
        '''
      }
    }
  }

  post {
    failure {
      echo 'Echec pipeline, rollback vers BLUE'
      script {
        withCredentials([sshUserPrivateKey(credentialsId: 'gitops-bot', keyFileVariable: 'SSH_KEY')]) {
          sh '''
            set -e
            rm -rf gitops && git clone -b "$GITOPS_BRANCH" "$GITOPS_REPO_SSH" gitops
            cd gitops
            git config user.name "$GIT_USER_NAME"
            git config user.email "$GIT_USER_EMAIL"
            yq -i '(.spec.selector.color) = "blue"' environments/prod/service.yaml
            git add environments/prod/service.yaml
            git commit -m "ci: rollback traffic to blue (pipeline failure)"
            git push origin "$GITOPS_BRANCH"
          '''
        }
      }
    }
  }
}