data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${local.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "Least-privilege runtime role for Butterfly Room staging"
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-ec2-role"
  role = aws_iam_role.app.name
}

data "aws_iam_policy_document" "app" {
  statement {
    sid    = "ListStagingBucket"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.app.arn]
  }

  statement {
    sid    = "ManageStagingObjects"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.app.arn}/*"]
  }

  statement {
    sid    = "ReadGoogleSheetsCredentialsSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]
    resources = [data.external.google_sheets_credentials_secret.result.arn]
  }

  statement {
    sid       = "CreateTaggedStagingStages"
    effect    = "Allow"
    actions   = ["ivs:CreateStage"]
    resources = ["arn:aws:ivs:${local.aws_region}:${data.aws_caller_identity.current.account_id}:stage/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/app"
      values   = ["butterfly-room"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/env"
      values   = ["staging"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/store_id"
      values   = ["*"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/booth_id"
      values   = ["*"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["app", "env", "store_id", "booth_id"]
    }
  }

  statement {
    sid       = "TagStagingStages"
    effect    = "Allow"
    actions   = ["ivs:TagResource"]
    resources = ["arn:aws:ivs:${local.aws_region}:${data.aws_caller_identity.current.account_id}:stage/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/app"
      values   = ["butterfly-room"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/env"
      values   = ["staging"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/app"
      values   = ["butterfly-room"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/env"
      values   = ["staging"]
    }
  }

  statement {
    sid    = "UseTaggedStagingStages"
    effect = "Allow"
    actions = [
      "ivs:CreateParticipantToken",
      "ivs:DisconnectParticipant",
      "ivs:GetStage",
      "ivs:ListParticipants"
    ]
    resources = ["arn:aws:ivs:${local.aws_region}:${data.aws_caller_identity.current.account_id}:stage/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/app"
      values   = ["butterfly-room"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/env"
      values   = ["staging"]
    }
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "${local.name_prefix}-runtime"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
