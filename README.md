# ECS Deployment

A containerized application deployment on AWS ECS with CodeDeploy canary deployments and automated CI/CD.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Infrastructure Setup](#infrastructure-setup)
- [Application Deployment](#application-deployment)
- [Monitoring](#monitoring)
- [Cleanup](#cleanup)

## Architecture Overview

### Network Topology
- VPC with public and private subnets across 3 Availability Zones
- Application Load Balancer for traffic distribution
- Security groups with least-privilege access

### Infrastructure Components
- **ECS Cluster**: Fargate-based container orchestration
- **Application Load Balancer**: Routes traffic to ECS services with blue/green target groups
- **CodeDeploy**: AWS-native deployment service for canary deployments
- **ECR**: Container registry for Docker images
- **CloudWatch**: Logging, monitoring, and alarm-based rollback
- **IAM**: Least-privilege access controls with OIDC for GitHub Actions
- **S3**: Terraform state storage with versioning
- **VPC Endpoints**: Private access to ECR (API/DKR), CloudWatch Logs, and S3 without NAT gateways

### Deployment Strategy
- **CodeDeploy Canary Deployment with ALB Uptime Monitoring**:
  - Traffic pattern: 10% → 20% → 50% → 70% → 100% (every 1 minute)
  - ALB success rate monitoring at each stage (threshold: 99.5%)
  - Automatic abort and rollback if success rate < 99.5%
  - CloudWatch alarm integration
  - Task definition generated from template (`infrastructure/taskdef.json.tpl`)

## Prerequisites

Before you begin, ensure you have:

1. **AWS Account** with appropriate permissions (admin for initial setup)
2. **AWS CLI** installed and configured (`aws configure`)
3. **Terraform** >= 1.5.0 installed
4. **Docker** installed and running
5. **GitHub repository** (for CI/CD)
6. **Bash** shell (for running scripts)
7. **jq** installed (for JSON processing)

### Verify Prerequisites

```bash
# Check AWS CLI
aws --version

# Check Terraform
terraform version

# Check Docker
docker --version

# Check jq
jq --version
```

## Initial Setup

### 1. Clone the Repository

```bash
git clone https://github.com/mohammedrampurawala1111/tech-assesment.git
cd tech-assesment
```

### 2. Configure AWS Credentials

Set up AWS credentials for local development (required for initial setup):

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter default region (e.g., eu-central-1)
# Enter default output format (json)
```

### 3. Set Up GitHub OIDC for CI/CD

The project uses GitHub Actions with OIDC (no long-lived AWS keys needed). Run the initialization script to set up all required AWS resources:

```bash
# Edit scripts/init.sh and update these variables:
# - ACCOUNT_ID: Your AWS account ID
# - AWS_REGION: Your AWS region (default: eu-central-1)
# - PROJECT_NAME: Project name (default: surepay)
# - GITHUB_REPO_SLUG: Your GitHub repo (format: owner/repo)
# - TF_STATE_BUCKET: S3 bucket name for Terraform state

# Run the initialization script
./scripts/init.sh
```

This script will:
- Create IAM OIDC provider for GitHub Actions
- Create IAM role for GitHub Actions (`surepay-github-oidc-role`)
- Create IAM policy with necessary permissions (ECR, ECS, CodeDeploy, Terraform, S3, etc.)
- Create S3 bucket for Terraform state (with versioning and public access blocking)
- Output the IAM role ARN for use in GitHub workflows

**Note**: The script requires AWS admin permissions to create IAM resources and S3 buckets.

### 4. Update GitHub Workflow Configuration

After running `init.sh`, the script will output the IAM role ARN. Update the GitHub workflows:

1. Open `.github/workflows/terraform.yml` and `.github/workflows/deploy.yml`
2. Update `AWS_ROLE_ARN` environment variable with the role ARN from the script output:
   ```yaml
   env:
     AWS_ROLE_ARN: arn:aws:iam::YOUR_ACCOUNT_ID:role/surepay-github-oidc-role
   ```

## Infrastructure Setup

### 1. Configure Terraform Variables (Optional)

Terraform uses default values, but you can customize by creating `terraform.tfvars`:

```bash
cd infrastructure
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
project_name = "surepay"
environment  = "prod"
aws_region   = "eu-central-1"

# Network configuration
vpc_cidr              = "10.0.0.0/16"
public_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs  = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
availability_zones    = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]

# Container configuration
container_cpu    = 512
container_memory = 2048
container_port   = 3000

# ECS service configuration
desired_count = 2
```

**Note**: The S3 backend bucket name is hardcoded in `infrastructure/backend.tf` as `surepay-tf-state`. Ensure this matches the bucket created by `init.sh` or update it accordingly.

### 2. Initialize Terraform

```bash
cd infrastructure
terraform init
```

This will:
- Download required providers
- Configure the S3 backend for state storage

### 3. Plan Infrastructure Changes

```bash
terraform plan
```

Review the planned changes carefully.

### 4. Apply Infrastructure

**Option A: Using GitHub Actions (Recommended)**

1. Push your infrastructure changes to GitHub:
   ```bash
   git add infrastructure/
   git commit -m "Add infrastructure configuration"
   git push origin main
   ```

2. The Terraform workflow (`.github/workflows/terraform.yml`) will:
   - Validate Terraform on pull requests
   - Plan infrastructure changes
   - Apply infrastructure on push to main (when changes are in `infrastructure/` directory)

**Option B: Manual Apply (Local)**

```bash
cd infrastructure
terraform apply
```

Type `yes` when prompted. This will create:
- VPC, subnets, VPC endpoints (ECR API/DKR, CloudWatch Logs, S3), internet gateway
- Application Load Balancer with blue/green target groups
- ECS cluster and service
- ECR repository
- IAM roles and policies for ECS tasks and CodeDeploy
- CodeDeploy application and deployment group
- CloudWatch log groups and alarms
- Initial task definition (for service creation)

**Note**: This process takes approximately 10-15 minutes.

### 5. Get Infrastructure Outputs

After infrastructure is created, get important values:

```bash
cd infrastructure
terraform output
```

Key outputs:
- `alb_dns_name`: Application Load Balancer DNS name
- `ecr_repository_url`: ECR repository URL for pushing images
- `cluster_name`: ECS cluster name
- `service_name`: ECS service name
- `codedeploy_app_name`: CodeDeploy application name
- `codedeploy_deployment_group_name`: CodeDeploy deployment group name

## Application Deployment

### Deploy via GitHub Actions Pipeline

The deployment is fully automated via GitHub Actions. Simply:

1. **Configure deployment settings** in `deploy.config`:
   ```bash
   # Container Configuration
   CPU=512
   MEMORY=2048
   CONTAINER_PORT=3000

   # Image Configuration
   TAG=v1.0                    # Change this for new versions
   IMAGE=                      # Leave empty, will be constructed from ECR URL + TAG

   # CodeDeploy Configuration
   DEPLOYMENT_CONFIG=CodeDeployDefault.ECSLinear10PercentEvery1Minutes
   ```

2. **Push changes to GitHub**:
   ```bash
   git add application/ deploy.config
   git commit -m "Deploy version v1.0"
   git push origin main
   ```

3. **The GitHub Actions workflow will automatically**:
   - Build Docker image for `linux/amd64` platform
   - Tag image with `TAG` from `deploy.config`
   - Push to ECR
   - Scan image with Trivy (security scanning)
   - Generate task definition from `infrastructure/taskdef.json.tpl` using values from `deploy.config`
   - Register new task definition revision
   - Create AppSpec file for CodeDeploy
   - Upload AppSpec to S3
   - Create CodeDeploy deployment
   - Monitor deployment progress

**Workflow Triggers**:
- Automatic: Push to `main` or `develop` branch when changes are in:
  - `application/` directory
  - `deploy.config` file
  - `.github/workflows/deploy.yml`
- Manual: Use GitHub Actions UI to trigger workflow with optional deployment strategy

### Monitor Deployment

The workflow will output the deployment ID and monitoring URL. You can also:

- **Check GitHub Actions logs**: View real-time deployment progress
- **AWS CLI**:
  ```bash
  # Get deployment ID from workflow output, then:
  aws deploy get-deployment --deployment-id <DEPLOYMENT_ID> --region eu-central-1
  ```

## Monitoring

### CloudWatch Logs

View application logs:

```bash
aws logs tail /ecs/surepay --follow --region eu-central-1
```

### CloudWatch Metrics

Key metrics to monitor:
- **ECS Service**: `CPUUtilization`, `MemoryUtilization`
- **ALB**: `TargetResponseTime`, `HTTPCode_Target_2XX_Count`, `HTTPCode_Target_4XX_Count`, `HTTPCode_Target_5XX_Count`
- **CodeDeploy**: Deployment status and progress
- **ALB Success Rate**: Monitored by CloudWatch alarm (threshold: 99.5%)

### Health Checks

The application exposes a health endpoint:
- **URL**: `http://<ALB_DNS>/health`
- **Expected**: `{"status":"healthy","timestamp":"..."}`


### CloudWatch Alarm

The deployment includes a CloudWatch alarm that monitors ALB success rate:
- **Alarm Name**: `surepay-alb-success-rate`
- **Threshold**: 99.5% success rate
- **Evaluation Periods**: 3
- **Datapoints to Alarm**: 2
- **Action**: Stops CodeDeploy deployment if threshold is breached

## Cleanup

### Destroy Infrastructure

To remove all AWS resources:

```bash
cd infrastructure
terraform destroy
```

Type `yes` when prompted. This will remove:
- All infrastructure resources (VPC, subnets, VPC endpoints, etc.)
- ECS cluster and service
- ECR repository (images will be deleted)
- CloudWatch log groups and alarms
- CodeDeploy application and deployment groups
- ALB and target groups

**Note**: 
- This is irreversible. Ensure you have backups if needed.
- The S3 bucket created by `init.sh` is NOT destroyed by Terraform (it's managed separately)
- To remove OIDC resources, manually delete the IAM role, policy, and OIDC provider


## Project Structure

```
├── application/                    # Application source code
│   ├── server.js                   # Express.js application
│   ├── Dockerfile                  # Container definition
│   ├── package.json                # Node.js dependencies
│   └── package-lock.json           # Dependency lock file
├── infrastructure/                 # Terraform infrastructure
│   ├── ecs.tf                      # ecs infrastructure resources
│   ├── vpc.tf                      # VPC resources
│   ├── sg.tf                       # security groups
│   ├── ecr.tf                      # elastic container registry
│   ├── cw.tf                       # cloud watch alarm
│   ├── variables.tf                # Variable definitions
│   ├── outputs.tf                  # Output values
│   ├── backend.tf                  # Terraform backend configuration (S3)
│   ├── taskdef.json.tpl            # Task definition template
│   └── terraform.tfvars.example    # Example Terraform variables
├── scripts/                        # Deployment scripts
│   ├── init.sh                     # AWS setup script (OIDC, IAM, S3)
│   ├── deploy_codedeploy_only.sh   # CodeDeploy deployment script
│   └── init.sh                     # add oidc and iam role for github
├── .github/workflows/              # CI/CD pipelines
│   ├── deploy.yml                  # Application deployment workflow
│   └── terraform.yml               # Infrastructure workflow
├── codedeploy/                     # CodeDeploy artifacts
│   └── appspec.yml                 # CodeDeploy AppSpec file (generated)
├── deploy.config                   # Deployment configuration
├── README.md                       # This file
└── ARCHITECTURE.md                 # Detailed architecture documentation with ADRs
```

## Security Best Practices

1. **Never commit AWS credentials** - Use OIDC for CI/CD
2. **Use least-privilege IAM policies** - Only grant necessary permissions
3. **Enable encryption** - ECR images, S3 buckets (versioning enabled)
4. **Private subnets** - ECS tasks run in private subnets
5. **Security groups** - Minimal required ports (ALB: 80/443, ECS: container port from ALB only)
6. **Secrets management** - Use AWS Secrets Manager or Parameter Store for sensitive data
7. **Regular updates** - Keep dependencies and base images updated
8. **Container scanning** - Trivy scans images in CI/CD pipeline
9. **State encryption** - Terraform state stored in S3 with encryption
