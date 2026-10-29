data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only the first two AZs are used (slice below), so new AZs cannot change placement.
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# Private application subnets in two AZs. There is no internet gateway and no
# NAT gateway: nothing in this VPC can reach, or be reached from, the internet
# (ADR-003).
resource "aws_subnet" "app" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 10 + count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name_prefix}-app-${local.azs[count.index]}", tier = "app" }
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-app-rt" }
}

resource "aws_route_table_association" "app" {
  count = length(aws_subnet.app)

  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

# S3 gateway endpoint: free, keeps PHI traffic on the AWS network, and its
# policy stops the VPC from writing to buckets in any other account.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app.id]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OnlyThisAccountsBuckets"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:*"
      Resource  = "*"
      Condition = {
        StringEquals = { "aws:ResourceAccount" = var.account_id }
      }
    }]
  })

  tags = { Name = "${var.name_prefix}-s3-endpoint" }
}

# The default security group allows all traffic between its members. Strip it
# so nothing can use it by accident (CIS AWS 5.4).
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-default-sg-closed" }
}

resource "aws_security_group" "app" {
  #checkov:skip=CKV2_AWS_5:Attached to the Lambda in the app module; checkov cannot follow cross-module references.
  name        = "${var.name_prefix}-app"
  description = "PHI reader Lambda: no inbound, HTTPS out to S3 only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-app" }
}

resource "aws_vpc_security_group_egress_rule" "app_to_s3" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to S3 through the gateway endpoint"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
}

# Network ACL for the app subnets. NACLs are stateless, so return traffic from
# S3 needs the ephemeral-port rule. No admin ports are open in either direction.
resource "aws_network_acl" "app" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.app[*].id

  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Ephemeral return ports, split so the RDP port (3389) is never open.
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 3388
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 3390
    to_port    = 65535
  }

  tags = { Name = "${var.name_prefix}-app-nacl" }
}

# Default NACL with no rules = deny all, for any subnet created outside Terraform.
resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.this.default_network_acl_id
  tags                   = { Name = "${var.name_prefix}-default-nacl-deny" }

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

# VPC Flow Logs: every accepted and rejected flow, to the audit log bucket.
resource "aws_flow_log" "vpc" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = "${var.flow_log_bucket_arn}/vpc-flow-logs/"
  max_aggregation_interval = 600

  destination_options {
    file_format                = "parquet"
    per_hour_partition         = true
    hive_compatible_partitions = true
  }

  tags = { Name = "${var.name_prefix}-flow-logs" }
}
