locals {
  create_cloudwatch_iam_role  = var.log_destination_type != "s3" && var.create_cloudwatch_iam_role
  create_cloudwatch_log_group = var.log_destination_type != "s3" && var.create_cloudwatch_log_group

  destination_arn       = local.create_cloudwatch_log_group ? aws_cloudwatch_log_group.this[0].arn : var.destination_arn
  flow_log_iam_role_arn = var.log_destination_type != "s3" && local.create_cloudwatch_iam_role ? aws_iam_role.this[0].arn : var.cloudwatch_iam_role_arn
}

################################################################################
# Flow Log
################################################################################

resource "aws_flow_log" "this" {
  log_destination_type     = var.log_destination_type
  log_destination          = local.destination_arn
  log_format               = var.log_format
  iam_role_arn             = local.flow_log_iam_role_arn
  traffic_type             = var.traffic_type
  vpc_id                   = var.vpc_id
  max_aggregation_interval = var.max_aggregation_interval

  dynamic "destination_options" {
    for_each = var.log_destination_type == "s3" ? [true] : []

    content {
      file_format                = var.file_format
      hive_compatible_partitions = var.hive_compatible_partitions
      per_hour_partition         = var.per_hour_partition
    }
  }

  lifecycle {
    ignore_changes = [
      log_destination,
    ]
  }
  tags = merge(var.tags, var.vpc_flow_log_tags)
}

################################################################################
# Flow Log CloudWatch
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  count = local.create_cloudwatch_log_group ? 1 : 0

  name_prefix       = var.log_group_name_prefix
  retention_in_days = var.cloudwatch_log_group_retention_in_days
  kms_key_id        = var.cloudwatch_log_group_kms_key_id

  tags = merge(var.tags, var.vpc_flow_log_tags)

  lifecycle {
    ignore_changes = [
      name_prefix,
    ]
  }
}

resource "aws_iam_role" "this" {
  count = local.create_cloudwatch_iam_role ? 1 : 0

  name_prefix          = var.iam_role_name_prefix
  assume_role_policy   = data.aws_iam_policy_document.cloudwatch_assume_role[0].json
  permissions_boundary = var.permissions_boundary

  inline_policy {
    name   = "LogRolePolicy"
    policy = data.aws_iam_policy_document.cloudwatch[0].json
  }

  tags = merge(var.tags, var.vpc_flow_log_tags)

  lifecycle {
    ignore_changes = [
      name_prefix,
    ]
  }
}

data "aws_iam_policy_document" "cloudwatch_assume_role" {
  count = local.create_cloudwatch_iam_role ? 1 : 0

  statement {
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    effect = "Allow"

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "cloudwatch" {
  count = local.create_cloudwatch_iam_role ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["${local.destination_arn}:*/*", "${local.destination_arn}:*"]
  }
}
