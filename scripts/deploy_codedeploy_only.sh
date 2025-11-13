#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load deployment configuration
CONFIG_FILE="${PROJECT_ROOT}/deploy.config"
if [[ -f "$CONFIG_FILE" ]]; then
  echo "Loading configuration from $CONFIG_FILE"
  set -a  
  source "$CONFIG_FILE"
  set +a 
fi

AWS_REGION="${AWS_REGION:-eu-central-1}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DEPLOYMENT_CONFIG="${DEPLOYMENT_CONFIG:-CodeDeployDefault.ECSLinear10PercentEvery1Minutes}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --image)
      IMAGE_URL="$2"
      shift 2
      ;;
    --tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --config)
      DEPLOYMENT_CONFIG="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

TERRAFORM_DIR="$PROJECT_ROOT/infrastructure"
if [[ -d "$TERRAFORM_DIR" ]] && command -v terraform &> /dev/null; then
  cd "$TERRAFORM_DIR"
  if terraform output -json codedeploy_app_name &> /dev/null; then
    APP_NAME="${APP_NAME:-$(terraform output -raw codedeploy_app_name 2>/dev/null)}"
    DEPLOYMENT_GROUP="${DEPLOYMENT_GROUP:-$(terraform output -raw codedeploy_deployment_group_name 2>/dev/null)}"
    CLUSTER="${CLUSTER:-$(terraform output -raw cluster_name 2>/dev/null)}"
    SERVICE="${SERVICE:-$(terraform output -raw service_name 2>/dev/null)}"
  fi
  cd "$PROJECT_ROOT"
fi

if [[ -z "$APP_NAME" ]] || [[ -z "$DEPLOYMENT_GROUP" ]]; then
  echo -e "${RED}Error: CodeDeploy app name and deployment group required${NC}"
  echo "Run 'terraform apply' first or provide --app and --group"
  exit 1
fi

# Get infrastructure values from Terraform
TERRAFORM_DIR="$PROJECT_ROOT/infrastructure"
if [[ -d "$TERRAFORM_DIR" ]] && command -v terraform &> /dev/null; then
  cd "$TERRAFORM_DIR"
  
  # Get IAM role ARNs
  EXECUTION_ROLE_ARN="${EXECUTION_ROLE_ARN:-$(terraform output -raw ecs_task_execution_role_arn 2>/dev/null || echo "")}"
  TASK_ROLE_ARN="${TASK_ROLE_ARN:-$(terraform output -raw ecs_task_role_arn 2>/dev/null || echo "")}"
  
  # Get CloudWatch log group
  LOG_GROUP="${LOG_GROUP:-$(terraform output -raw ecs_log_group 2>/dev/null || echo "")}"
  
  # Get task definition family (defaults to PROJECT_NAME-app)
  TASK_DEF_FAMILY="${PROJECT_NAME:-surepay}-app"
  
  cd "$PROJECT_ROOT"
fi

# Validate required variables
if [[ -z "$EXECUTION_ROLE_ARN" ]] || [[ -z "$TASK_ROLE_ARN" ]] || [[ -z "$LOG_GROUP" ]]; then
  echo -e "${RED}Error: Missing required infrastructure values${NC}"
  echo "Run 'terraform apply' first to create IAM roles and log groups"
  echo "Or set EXECUTION_ROLE_ARN, TASK_ROLE_ARN, and LOG_GROUP in deploy.config"
  exit 1
fi

# Determine full image URL (check if IMAGE_URL already contains a tag or use IMAGE from config)
if [[ -n "$IMAGE_URL" ]]; then
  # Check if IMAGE_URL already contains a tag (has colon after the last /)
  if [[ "$IMAGE_URL" =~ :[^/]+$ ]]; then
    FULL_IMAGE="$IMAGE_URL"
  else
    FULL_IMAGE="${IMAGE_URL}:${IMAGE_TAG}"
  fi
elif [[ -n "$IMAGE" ]]; then
  # Use IMAGE from config file
  if [[ "$IMAGE" =~ :[^/]+$ ]]; then
    FULL_IMAGE="$IMAGE"
  else
    FULL_IMAGE="${IMAGE}:${IMAGE_TAG}"
  fi
fi

echo -e "${GREEN}Starting CodeDeploy canary deployment${NC}"
echo "Configuration:"
if [[ -n "$FULL_IMAGE" ]]; then
  echo "  Image: $FULL_IMAGE"
elif [[ -n "$IMAGE_URL" ]] || [[ -n "$IMAGE" ]]; then
  echo "  Image: $FULL_IMAGE"
else
  echo "  Image: Using latest task definition version (no image specified)"
fi
echo "  CPU: ${CPU}"
echo "  Memory: ${MEMORY} MB"
echo "  Container Port: ${CONTAINER_PORT}"
echo "  Deployment Config: $DEPLOYMENT_CONFIG"
echo "  App: $APP_NAME"
echo "  Deployment Group: $DEPLOYMENT_GROUP"
echo "  Task Definition Family: $TASK_DEF_FAMILY"
echo ""

# Step 1: Generate task definition from template
if [[ -n "$FULL_IMAGE" ]]; then
  # Create new task definition from template
  echo -e "${YELLOW}Step 1: Generating task definition from template...${NC}"
  
  TASK_DEF_TEMPLATE="${PROJECT_ROOT}/infrastructure/taskdef.json.tpl"
  if [[ ! -f "$TASK_DEF_TEMPLATE" ]]; then
    echo -e "${RED}Error: Task definition template not found: $TASK_DEF_TEMPLATE${NC}"
    exit 1
  fi
  
  # Export variables for envsubst
  export PROJECT_NAME CPU MEMORY CONTAINER_PORT ENVIRONMENT AWS_REGION
  export EXECUTION_ROLE_ARN TASK_ROLE_ARN LOG_GROUP
  export IMAGE="$FULL_IMAGE"
  
  # Validate required variables
  if [[ -z "$PROJECT_NAME" ]] || [[ -z "$CPU" ]] || [[ -z "$MEMORY" ]] || [[ -z "$CONTAINER_PORT" ]]; then
    echo -e "${RED}Error: Missing required variables (PROJECT_NAME, CPU, MEMORY, CONTAINER_PORT)${NC}"
    echo "Check deploy.config file"
    exit 1
  fi
  
  if [[ -z "$EXECUTION_ROLE_ARN" ]] || [[ -z "$TASK_ROLE_ARN" ]] || [[ -z "$LOG_GROUP" ]]; then
    echo -e "${RED}Error: Missing required infrastructure values${NC}"
    echo "Run 'terraform apply' first or set EXECUTION_ROLE_ARN, TASK_ROLE_ARN, and LOG_GROUP in deploy.config"
    exit 1
  fi
  
  # Generate task definition JSON from template
  TASK_DEF_JSON=$(envsubst '$PROJECT_NAME $CPU $MEMORY $CONTAINER_PORT $ENVIRONMENT $AWS_REGION $EXECUTION_ROLE_ARN $TASK_ROLE_ARN $LOG_GROUP $IMAGE' < "$TASK_DEF_TEMPLATE")
  
  TASK_DEF_FILE=$(mktemp)
  trap "rm -f $TASK_DEF_FILE" EXIT
  echo "$TASK_DEF_JSON" > "$TASK_DEF_FILE"
  
  # Validate JSON
  if ! jq empty "$TASK_DEF_FILE" 2>/dev/null; then
    echo -e "${RED}Error: Generated task definition is invalid JSON${NC}"
    echo "Generated JSON:"
    cat "$TASK_DEF_FILE"
    echo ""
    echo "Variables:"
    echo "  PROJECT_NAME: $PROJECT_NAME"
    echo "  CPU: $CPU"
    echo "  MEMORY: $MEMORY"
    echo "  CONTAINER_PORT: $CONTAINER_PORT"
    echo "  EXECUTION_ROLE_ARN: $EXECUTION_ROLE_ARN"
    echo "  TASK_ROLE_ARN: $TASK_ROLE_ARN"
    echo "  LOG_GROUP: $LOG_GROUP"
    echo "  IMAGE: $IMAGE"
    exit 1
  fi
  
  # Show task definition summary
  echo "Task definition configuration:"
  jq '{family, cpu, memory, image: .containerDefinitions[0].image, containerPort: .containerDefinitions[0].portMappings[0].containerPort}' "$TASK_DEF_FILE"
  
  # Register task definition
  NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json "file://$TASK_DEF_FILE" \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)
  
  if [[ -z "$NEW_TASK_DEF_ARN" ]]; then
    echo -e "${RED}Error: Failed to register task definition${NC}"
    echo "Task definition JSON:"
    cat "$TASK_DEF_FILE"
    exit 1
  fi
  
  echo -e "${GREEN}✓ Task definition registered: $NEW_TASK_DEF_ARN${NC}"
else
  # Use latest task definition version
  echo -e "${YELLOW}Step 1: Getting latest task definition version...${NC}"
  
  # List all task definitions for the family, sorted DESC to get latest first
  LATEST_TASK_DEF=$(aws ecs list-task-definitions \
    --family-prefix "$TASK_DEF_FAMILY" \
    --region "$AWS_REGION" \
    --sort DESC \
    --max-items 1 \
    --query 'taskDefinitionArns[0]' \
    --output text)
  
  if [[ -z "$LATEST_TASK_DEF" ]] || [[ "$LATEST_TASK_DEF" == "None" ]]; then
    echo -e "${RED}Error: No task definitions found for family: $TASK_DEF_FAMILY${NC}"
    echo "Create a task definition first using --image flag"
    exit 1
  fi
  
  NEW_TASK_DEF_ARN="$LATEST_TASK_DEF"
  # Extract revision number for display
  REVISION=$(echo "$NEW_TASK_DEF_ARN" | awk -F: '{print $NF}')
  echo "Using latest task definition (revision $REVISION): $NEW_TASK_DEF_ARN"
  
  # Get task definition details to show what's being deployed
  TASK_DEF_INFO=$(aws ecs describe-task-definition \
    --task-definition "$NEW_TASK_DEF_ARN" \
    --region "$AWS_REGION" \
    --query '{Image:taskDefinition.containerDefinitions[0].image,CPU:taskDefinition.cpu,Memory:taskDefinition.memory,Revision:taskDefinition.revision}' \
    --output json)
  
  echo "Task definition details:"
  echo "$TASK_DEF_INFO" | jq '.'
fi

# Step 2: Create AppSpec file
echo -e "${YELLOW}Step 2: Creating AppSpec file...${NC}"

cd "$PROJECT_ROOT"
mkdir -p codedeploy

# Get container name and port from Terraform if not provided
TERRAFORM_DIR="$PROJECT_ROOT/infrastructure"
CONTAINER_NAME="${CONTAINER_NAME:-surepay-app}"
CONTAINER_PORT="${CONTAINER_PORT:-3000}"

if [[ -d "$TERRAFORM_DIR" ]] && command -v terraform &> /dev/null; then
  cd "$TERRAFORM_DIR"
  if terraform output -json container_name &> /dev/null; then
    CONTAINER_NAME=$(terraform output -raw container_name 2>/dev/null || echo "$CONTAINER_NAME")
    CONTAINER_PORT=$(terraform output -raw container_port 2>/dev/null || echo "$CONTAINER_PORT")
  fi
  cd "$PROJECT_ROOT"
fi

cat > codedeploy/appspec.yml <<EOF
version: 0.0
Resources:
  - TargetService:
      Type: AWS::ECS::Service
      Properties:
        TaskDefinition: "$NEW_TASK_DEF_ARN"
        LoadBalancerInfo:
          ContainerName: "$CONTAINER_NAME"
          ContainerPort: $CONTAINER_PORT
EOF

echo "Created AppSpec with ContainerName: $CONTAINER_NAME, ContainerPort: $CONTAINER_PORT"

# Step 3: Create deployment package
echo -e "${YELLOW}Step 3: Creating deployment package...${NC}"

cd codedeploy
zip -q deployment.zip appspec.yml
cd ..

# Step 4: Upload to S3
echo -e "${YELLOW}Step 4: Uploading to S3...${NC}"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET="codedeploy-${AWS_REGION}-${AWS_ACCOUNT_ID}"
TASK_DEF_REVISION=$(echo "$NEW_TASK_DEF_ARN" | awk -F: '{print $NF}')
S3_KEY="deployments/$(date +%Y%m%d%H%M%S)-rev${TASK_DEF_REVISION}.zip"

aws s3 mb "s3://${S3_BUCKET}" --region "$AWS_REGION" 2>/dev/null || true
aws s3 cp codedeploy/deployment.zip "s3://${S3_BUCKET}/${S3_KEY}" --region "$AWS_REGION"

echo "Uploaded to s3://${S3_BUCKET}/${S3_KEY}"

# Step 5: Determine deployment config (use all-at-once for first deployment)
echo -e "${YELLOW}Step 5: Determining deployment configuration...${NC}"

# Check if this is the first deployment
PREVIOUS_DEPLOYMENTS=$(aws deploy list-deployments \
  --application-name "$APP_NAME" \
  --deployment-group-name "$DEPLOYMENT_GROUP" \
  --region "$AWS_REGION" \
  --max-items 1 \
  --query 'deploymentsIds[]' \
  --output text 2>/dev/null || echo "")

IS_FIRST_DEPLOYMENT=false
if [[ -z "$PREVIOUS_DEPLOYMENTS" ]] || [[ "$PREVIOUS_DEPLOYMENTS" == "None" ]]; then
  IS_FIRST_DEPLOYMENT=true
  echo "  This is the first deployment"
fi

# Use all-at-once deployment for first run (no canary, immediate deployment)
ACTUAL_DEPLOYMENT_CONFIG="$DEPLOYMENT_CONFIG"
if [[ "$IS_FIRST_DEPLOYMENT" == "true" ]]; then
  ACTUAL_DEPLOYMENT_CONFIG="CodeDeployDefault.ECSAllAtOnce"
  echo "  Using all-at-once deployment (first deployment)"
  echo "  This will deploy all tasks immediately without canary rollout"
  echo "  Subsequent deployments will use canary strategy: $DEPLOYMENT_CONFIG"
else
  echo "  Using configured canary deployment: $DEPLOYMENT_CONFIG"
fi

# Step 6: Create CodeDeploy deployment
echo -e "${YELLOW}Step 6: Creating CodeDeploy deployment...${NC}"

DEPLOYMENT_ID=$(aws deploy create-deployment \
  --application-name "$APP_NAME" \
  --deployment-group-name "$DEPLOYMENT_GROUP" \
  --deployment-config-name "$ACTUAL_DEPLOYMENT_CONFIG" \
  --s3-location bucket="$S3_BUCKET",key="$S3_KEY",bundleType=zip \
  --region "$AWS_REGION" \
  --query 'deploymentId' \
  --output text)

echo -e "${GREEN}Deployment created successfully!${NC}"
echo ""
echo "Deployment ID: $DEPLOYMENT_ID"
echo "Deployment Config: $ACTUAL_DEPLOYMENT_CONFIG"
if [[ "$ACTUAL_DEPLOYMENT_CONFIG" != "CodeDeployDefault.ECSAllAtOnce" ]]; then
  echo "CloudWatch alarm will stop deployment if ALB uptime < 99.99%"
fi
echo ""
echo "Check status:"
echo "  aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --region $AWS_REGION"
