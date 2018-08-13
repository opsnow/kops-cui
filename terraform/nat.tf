
variable region {
  default = "REGION"
}

variable kops_cluster_name {
  default = "KOPS_CLUSTER_NAME"
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
}

resource "aws_nat_gateway" "this" {
  count = "${length(local.subnet_ids)}"

  allocation_id = "${element(aws_eip.nat.*.id, count.index)}"
  subnet_id     = "${element(local.subnet_ids, count.index)}"
}

output "nat_ips" {
  value = "${aws_eip.nat.*.public_ip}"
}
