# Architecture Documentation

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ HTTPS/HTTP
                         │
         ┌───────────────▼────────────────┐
         │   Application Load Balancer    │
         │      (Public Subnets)          │
         └───────────────┬────────────────┘
                         │
                         │ Port 3000
                         │
         ┌───────────────▼────────────────┐
         │      Target Group             │
         │   (Health Checks: /health)    │
         └───────────────┬────────────────┘
                         │
                         │
         ┌───────────────▼────────────────┐
         │      ECS Service (Fargate)    │
         │      (Private Subnets)        │
         │                               │
         │  ┌──────────┐  ┌──────────┐  │
         │  │ Task 1   │  │ Task 2   │  │
         │  │ Container│  │ Container│  │
         │  └──────────┘  └──────────┘  │
         └───────────────────────────────┘
```

## Network Topology

### VPC Structure

```
VPC: 10.0.0.0/16
│
├── Public Subnets (3 AZs)
│   ├── eu-central-1a: 10.0.1.0/24  [ALB]
│   ├── eu-central-1b: 10.0.2.0/24  [ALB]
│   └── eu-central-1c: 10.0.3.0/24  [ALB]
│
└── Private Subnets (3 AZs)
    ├── eu-central-1a: 10.0.11.0/24 [ECS Tasks, VPC Endpoints]
    ├── eu-central-1b: 10.0.12.0/24 [ECS Tasks, VPC Endpoints]
    └── eu-central-1c: 10.0.13.0/24 [ECS Tasks, VPC Endpoints]
```

### Security Groups

**ALB Security Group:**
- Inbound: HTTP (80), HTTPS (443) from 0.0.0.0/0
- Outbound: All traffic

**ECS Tasks Security Group:**
- Inbound: Port 3000 from ALB security group only
- Outbound: All traffic (private connectivity to AWS services via VPC endpoints)

## Infrastructure Components

### 1. VPC and Networking
- **VPC**: Isolated network environment
- **Subnets**: 3 public (ALB) + 3 private (ECS tasks) across AZs
- **Internet Gateway**: Provides public internet access for ALB
- **VPC Endpoints**: Interface endpoints for ECR & CloudWatch Logs, gateway endpoint for S3
- **Route Tables**: Separate routes for public/private subnets

### 2. ECS Components
- **ECS Cluster**: Fargate-based cluster (no EC2 management)
- **Task Definition**: Container specification (CPU, memory, image)
- **Service**: Maintains desired count of tasks, handles deployments
- **Container**: Node.js application running in Docker

### 3. Load Balancing
- **Application Load Balancer**: HTTP/HTTPS load balancer
- **Target Group**: Routes traffic to ECS tasks
- **Health Checks**: Monitors `/health` endpoint every 30s

### 4. Container Registry
- **ECR**: Amazon Elastic Container Registry
- **Image Scanning**: Automatic security scanning on push
- **Lifecycle Policies**: Keeps last 10 images

### 5. Monitoring and Logging
- **CloudWatch Logs**: Application and container logs (implemented)
- **CloudWatch Metrics**: ECS service metrics, ALB metrics (implemented)
- **Container Insights**: Enhanced monitoring for ECS (implemented - enabled on cluster)
- **CloudWatch Alarm**: ALB success rate monitoring with automatic deployment rollback (implemented)

### 6. IAM Roles
- **Task Execution Role**: Pulls images from ECR, writes to CloudWatch
- **Task Role**: Application-level permissions (extensible)

## Deployment Strategies

### Canary Deployment (Implemented)

**Current Implementation:**
- **Deployment Type**: CodeDeploy with blue-green infrastructure and canary traffic shifting
- **Traffic Pattern**: 10% → 20% → 50% → 70% → 100% (every 1 minute)
- **Configuration**: `CodeDeployDefault.ECSLinear10PercentEvery1Minutes`
- **Monitoring**: CloudWatch alarm monitors ALB success rate (99.5% threshold)
- **Rollback**: Automatic rollback if alarm triggers during deployment

**Flow:**
1. Register new task definition with new image (from `taskdef.json.tpl` template)
2. CodeDeploy creates deployment with canary traffic shifting
3. Monitor health at each phase:
   - Phase 1 (10%): Monitor for 1 minute
   - Phase 2 (20%): Monitor for 1 minute
   - Phase 3 (50%): Monitor for 1 minute
   - Phase 4 (70%): Monitor for 1 minute
   - Phase 5 (100%): Complete rollout
4. CloudWatch alarm monitors success rate - stops deployment if < 99.5%

**Advantages:**
- Low risk - issues detected early
- Gradual traffic shift
- Automatic rollback on alarm trigger
- Deployment history and tracking

**Use Case:** Standard production deployments (currently implemented)

## Security Architecture

### Network Security
1. **Private Subnets**: ECS tasks have no public IPs (implemented)
2. **Security Groups**: Least-privilege rules (implemented)
3. **VPC Endpoints**: Private connectivity to AWS services (ECR API/DKR, CloudWatch Logs, S3) - no internet egress (implemented)

### Access Control
1. **IAM Roles**: Separate roles for execution vs. task
2. **Least Privilege**: Minimal permissions required
3. **No Public Access**: Tasks can't be directly accessed

### Data Security
1. **ECR Encryption**: Images encrypted at rest (AES256 - implemented)
2. **CloudWatch Logs**: Encrypted by default (implemented)
3. **VPC Flow Logs**: Not implemented

### Application Security
1. **Image Scanning**: ECR scans for vulnerabilities on push (implemented)
2. **Health Checks**: Automatic unhealthy target removal (ALB and container health checks - implemented)
3. **Trivy Scanning**: Container image security scanning in CI/CD pipeline (implemented)

## Scalability

### Horizontal Scaling
- **ALB**: Automatically distributes traffic across tasks (implemented)
- **Multi-AZ**: Tasks distributed across 3 availability zones (implemented)
- **Service Auto Scaling**: Not implemented

### Vertical Scaling
- Adjust CPU/memory in task definition via `deploy.config` (implemented)
- Fargate supports up to 4 vCPU and 30 GB memory (available)

## High Availability

### Multi-AZ Deployment
- Subnets and tasks in 3 availability zones (implemented)
- VPC Endpoints in each AZ for redundancy (implemented)
- ALB spans all AZs (implemented)

### Service Reliability
- Desired count maintained automatically (implemented)
- Failed tasks replaced automatically (implemented)
- Health checks remove unhealthy targets (ALB and container health checks - implemented)
- Circuit breaker: Not implemented (ECS service has deployment configuration but no explicit circuit breaker)

## CI/CD Pipeline

### GitHub Actions Workflow

**On Push to Main:**
1. **Test**: Run application tests
2. **Build**: Build Docker image
3. **Scan**: Security scan with Trivy
4. **Push**: Push to ECR
5. **Deploy**: Canary deployment to ECS
6. **Verify**: Confirm deployment success

### Manual Triggers
- Workflow dispatch (manual trigger available, but deployment strategy is fixed to canary)
- Terraform apply for infrastructure changes (via GitHub Actions or local)

## Design Decisions

### Why ECS Fargate?
- **No Server Management**: No EC2 instances to manage
- **Security**: No SSH access, reduced attack surface
- **Cost**: Pay only for running tasks
- **Scalability**: Auto-scaling without capacity planning
- **Integration**: Native AWS service integration

### Why Private Subnets?
- **Security**: No direct internet exposure
- **Best Practice**: AWS Well-Architected Framework recommendation
- **Network Control**: Better traffic control and monitoring

### Why Canary as Default?
- **Risk Mitigation**: Issues caught early with small user impact
- **Gradual Rollout**: Controlled traffic increase
- **User Experience**: Minimal disruption if issues arise
- **Industry Standard**: Common pattern in modern deployments

### Why Multi-AZ?
- **High Availability**: Survives single AZ failure
- **Performance**: Lower latency with regional distribution
- **Best Practice**: AWS recommended for production

## Cost Considerations

### Fixed Costs
- VPC Interface Endpoints: ~$7/month each 
- ALB: ~$16/month + data transfer

### Variable Costs
- ECS Fargate: ~$0.04/vCPU-hour + $0.004/GB-hour
- Example: 2 tasks x 0.5 vCPU x 1GB = ~$58/month
- Data transfer costs
- CloudWatch Logs: First 5GB free, then $0.50/GB

### Optimization Opportunities
- Use Fargate Spot (up to 70% savings) for non-critical workloads
- Right-size containers (avoid over-provisioning)
- Enable CloudWatch Logs retention (reduce storage costs)
- Add VPC endpoints only for required services to control costs

## Monitoring and Observability

### Metrics
- ECS: CPU, Memory, Task count, Deployment status
- ALB: Request count, Response times, Error rates
- CloudWatch: Custom application metrics

### Logs
- Application logs via CloudWatch Logs (implemented)
- Container logs (stdout/stderr) via CloudWatch Logs (implemented)

### Alarms
- **ALB Success Rate**: Monitors success rate during deployments (99.5% threshold, 2 datapoints) - implemented

## Disaster Recovery

### Backup Strategy
- Infrastructure: Terraform state (store in S3 with versioning)
- Application: Container images in ECR
- Configuration: Version controlled in Git

## Future Enhancements

### Infrastructure Improvements
1. **HTTPS/SSL**: Add ACM certificate and HTTPS listener to ALB
2. **Auto Scaling**: Configure ECS service auto-scaling based on CPU/memory/custom metrics
3. **VPC Flow Logs**: Enable network traffic logging for security analysis
4. **Additional CloudWatch Alarms**: High error rate, low healthy target count, deployment failures, high CPU/memory usage
5. **Circuit Breaker**: Implement explicit circuit breaker configuration for deployments
6. **WAF**: Web Application Firewall for ALB
7. **Multi-Region**: Deploy to multiple regions for global reach
8. **CDN**: Add CloudFront for static content

### Deployment Improvements
9. **Rolling Deployment**: Implement native ECS rolling deployment for dev/staging environments
10. **Blue-Green Deployment**: Full blue-green deployment strategy (currently using canary with blue-green infrastructure)
11. **Deployment Approval Gates**: Add manual approval steps for production deployments
12. **Automated Smoke Tests**: Add tests between canary phases

### Security Improvements
13. **Secrets Management**: Integrate AWS Secrets Manager or Parameter Store
14. **Container Security**: Verify and enforce non-root user in containers
15. **VPC Endpoints for Secrets**: Add interface endpoints for Secrets Manager/Parameter Store
16. **IP Restrictions**: Add IP restrictions for role assumption

### Operational Improvements
17. **Service Discovery**: Consider Cloud Map for service discovery
18. **Service Mesh**: Consider App Mesh for advanced traffic management
19. **Deployment Notifications**: Integrate with Slack/Teams for deployment notifications
20. **Custom Deployment Hooks**: Add pre/post-deployment tasks
21. **Task Definition Drift Detection**: Automatically detect and alert on task definition changes