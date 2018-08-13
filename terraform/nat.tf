# AWS NAT Gateway

variable name {
  default = "KOPS_CLUSTER_NAME"
}

variable vpc_id {
  default = "VPC_ID"
}

variable subnet_ids {
  default = "SUBNET_IDS"
}

provider "aws" {
  region = "REGION"
}

terraform {
  backend "s3" {
    region = "REGION"
    bucket = "KOPS_STATE_STORE"
    key = "KOPS_CLUSTER_NAME.tfstate"
  }
}

locals {
  subnet_ids = "${split(",", var.subnet_ids)}"
}

resource "aws_eip" "nat" {
  count = "${length(local.subnet_ids)}"

  vpc = true

  tags = {
    Name = "${var.name}",
    KubernetesCluster = "${var.name}"
  }
}

resource "aws_nat_gateway" "this" {
  count = "${length(local.subnet_ids)}"

  allocation_id = "${element(aws_eip.nat.*.id, count.index)}"
  subnet_id     = "${element(local.subnet_ids, count.index)}"

  tags = {
    Name = "${var.name}",
    KubernetesCluster = "${var.name}"
  }
}

resource "aws_route_table" "private" {
  count = "${length(local.subnet_ids)}"

  vpc_id = "${var.vpc_id}"

  lifecycle {
    ignore_changes = ["propagating_vgws"]
  }

  tags = {
    Name = "${var.name}-nat",
    KubernetesCluster = "${var.name}"
  }
}

# resource "aws_route_table_association" "private" {
#   count = "${length(local.subnet_ids)}"

#   subnet_id      = "${element(local.subnet_ids, count.index)}"
#   route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
# }

resource "aws_route" "private" {
  count = "${length(local.subnet_ids)}"

  route_table_id         = "${element(aws_route_table.private.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${element(aws_nat_gateway.this.*.id, count.index)}"

  timeouts {
    create = "5m"
  }
}

output "nat_ips" {
  value = "${aws_eip.nat.*.public_ip}"
}
