provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Name       = "hello-msk"
      Repository = "https://github.com/ericdahl/tf-msk-sandbox"
    }
  }
}

data "aws_default_tags" "default" {}

locals {
  name = data.aws_default_tags.default.tags["Name"]
}

resource "aws_security_group" "msk" {
  vpc_id = aws_vpc.default.id
}

resource "aws_security_group_rule" "msk_ingress_ec2" {
  from_port                = 9098
  protocol                 = "tcp"
  security_group_id        = aws_security_group.msk.id
  to_port                  = 9098
  type                     = "ingress"
  source_security_group_id = aws_security_group.ec2_debug.id
  description              = "allow ingress from ec2_debug"
}

# shouldn't be necessary TODO
resource "aws_security_group_rule" "msk_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1" # -1 indicates all protocols
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.msk.id
}


resource "aws_msk_cluster" "example" {
  cluster_name           = local.name
  kafka_version          = "3.7.x"
  number_of_broker_nodes = 2
  broker_node_group_info {
    client_subnets = values(aws_subnet.public)[*].id
    instance_type = "kafka.t3.small"
    security_groups = [aws_security_group.msk.id]
  }
  configuration_info {
    arn      = aws_msk_configuration.default.arn
    revision = aws_msk_configuration.default.latest_revision
  }

  client_authentication {
    sasl {
      iam  = true
    }
  }
}

resource "aws_msk_configuration" "default" {
  name              = local.name
  server_properties = <<EOF
auto.create.topics.enable = true
EOF
}


data "aws_msk_bootstrap_brokers" "example" {
  cluster_arn = aws_msk_cluster.example.arn
}

output "bootstrap" {
  value = data.aws_msk_bootstrap_brokers.example.bootstrap_brokers_sasl_iam
}

data "aws_iam_policy_document" "assume_policy_lambda" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}