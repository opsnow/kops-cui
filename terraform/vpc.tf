# VPC

# https://github.com/terraform-aws-modules/terraform-aws-vpc
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "vpc-VPC-NAME"
  cidr = "10.0.0.0/16"

  azs             = ["ap-northeast-2a","ap-northeast-2c"]
  private_subnets = ["10.0.11.0/24","10.0.12.0/24"]
  public_subnets  = ["10.0.21.0/24","10.0.22.0/24"]

  enable_nat_gateway = true
#   single_nat_gateway = false
#   one_nat_gateway_per_az = true

  enable_vpn_gateway = true

#   enable_dns_hostnames = true
#   enable_dns_support = true

  tags = {
    Terraform   = "true"
    Environment = "dev"

    "kubernetes.io/cluster/${var.kops_cluster_name}" = "shared"
  }
}

output "vpc_id" {
  value = "${module.vpc.vpc_id}"
}

output "vpc_cidr_block" {
  value = "${module.vpc.vpc_cidr_block}"
}

output "public_subnets" {
  value = "${module.vpc.public_subnets}"
}

output "public_subnets_cidr_blocks" {
  value = "${module.vpc.public_subnets_cidr_blocks}"
}

output "private_subnets" {
  value = "${module.vpc.private_subnets}"
}

output "private_subnets_cidr_blocks" {
  value = "${module.vpc.private_subnets_cidr_blocks}"
}

output "nat_public_ips" {
  value = "${module.vpc.nat_public_ips}"
}
