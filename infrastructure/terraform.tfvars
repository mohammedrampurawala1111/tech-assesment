aws_region   = "eu-central-1"
project_name = "surepay"
environment  = "staging"
vpc_cidr     = "10.0.0.0/16"

availability_zones   = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

container_cpu    = 512
container_memory = 1024
desired_count    = 2
container_port   = 3000

enable_canary = true
image_tag     = "latest"

