import groovy.json.JsonOutput

pipeline {
  agent any

  options {
    disableConcurrentBuilds()
    timestamps()
  }

  parameters {
    string(name: 'VPC_ID', description: 'Existing VPC ID, for example vpc-0123456789abcdef0')
    string(name: 'SUBNET_IDS', description: 'Comma-separated private subnet IDs in at least two Availability Zones')
    string(name: 'AWS_REGION', defaultValue: 'us-east-1', description: 'AWS region')
    choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'Terraform action to run')
  }

  environment {
    TF_IN_AUTOMATION = 'true'
    TF_INPUT = 'false'
  }

  stages {
    stage('Prepare') {
      steps {
        script {
          def subnetIds = params.SUBNET_IDS.split(',')
            .collect { it.trim() }
            .findAll { it }

          if (!params.VPC_ID.trim()) {
            error('VPC_ID is required')
          }
          if (subnetIds.size() < 2) {
            error('SUBNET_IDS must contain at least two comma-separated subnet IDs')
          }

          env.TF_VAR_vpc_id = params.VPC_ID.trim()
          env.TF_VAR_subnet_ids = JsonOutput.toJson(subnetIds)
          env.TF_VAR_aws_region = params.AWS_REGION.trim()
        }
      }
    }

    stage('Terraform init') {
      steps {
        sh 'terraform init -input=false'
      }
    }

    stage('Terraform validate') {
      steps {
        sh 'terraform validate'
      }
    }

    stage('Terraform plan') {
      when {
        expression { params.ACTION != 'destroy' }
      }
      steps {
        sh 'terraform plan -input=false -out=tfplan'
      }
    }

    stage('Terraform apply') {
      when {
        expression { params.ACTION == 'apply' }
      }
      steps {
        sh 'terraform apply -input=false -auto-approve tfplan'
      }
    }

    stage('Terraform destroy') {
      when {
        expression { params.ACTION == 'destroy' }
      }
      steps {
        input message: "Destroy ${params.VPC_ID}'s EKS resources?", ok: 'Destroy'
        sh 'terraform destroy -input=false -auto-approve'
      }
    }
  }

}
