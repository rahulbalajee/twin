# GitHub Actions OIDC federation — lets CI deploy without long-lived AWS keys.
#
# Account-level singletons (one OIDC provider per URL per account, fixed role
# name), so they live in bootstrap alongside the state bucket: applied once,
# shared by all environments, and immune to `destroy.sh <env>`.

variable "github_repository" {
  description = "GitHub repository allowed to assume the deploy role, in owner/repo format"
  type        = string
  default     = "rahulbalajee/twin"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Must be in owner/repo format, e.g. rahulbalajee/twin"
  }
}

# The account already has a GitHub OIDC provider (AWS allows one per URL per
# account; this one predates the twin, created 2025-11 by an earlier project).
# Reference it instead of managing it — importing would put two Terraform
# states in charge of one resource.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name        = "github-actions-twin-deploy"
  description = "Assumed by GitHub Actions in ${var.github_repository} (main branch) to deploy the twin stack"

  # The Condition block is the security boundary: without the sub claim check,
  # ANY GitHub repository's workflows could assume this role.
  #
  # Jobs that declare `environment:` get sub claims in the form
  # "repo:<owner/repo>:environment:<name>" (NOT "ref:refs/heads/<branch>"),
  # so the allowlist below matches the deploy workflow's environments.
  # Branch restriction is enforced GitHub-side via each environment's
  # "deployment branches" rule (set to main only).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_repository}:environment:dev",
              "repo:${var.github_repository}:environment:test",
              "repo:${var.github_repository}:environment:prod",
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name        = "GitHub Actions Role"
    Environment = "global"
    ManagedBy   = "terraform"
    Repository  = var.github_repository
  }
}

# Managed policies mirroring what the twin deploy actually touches.
# (No Bedrock: terraform only writes IAM policies referencing bedrock ARNs —
# it never calls the Bedrock API itself.)
resource "aws_iam_role_policy_attachment" "github_managed" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AWSLambda_FullAccess",
    "arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/CloudFrontFullAccess",
    "arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess",
    "arn:aws:iam::aws:policy/AmazonRoute53FullAccess",
    "arn:aws:iam::aws:policy/IAMReadOnlyAccess",
  ])

  role       = aws_iam_role.github_actions.name
  policy_arn = each.value
}

# IAM write access scoped to the twin's own roles. Scoping PassRole matters
# most: PassRole on "*" would let this role hand ANY role in the account
# (including admin ones) to a service — the classic escalation primitive.
resource "aws_iam_role_policy" "github_iam_scoped" {
  name = "github-actions-twin-deploy-iam"
  role = aws_iam_role.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "ManageTwinRolesOnly"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:UpdateAssumeRolePolicy",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListInstanceProfilesForRole",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/twin-*"
      }
    ]
  })
}

output "github_actions_role_arn" {
  description = "Set as AWS_ROLE_ARN in the GitHub workflow's aws-actions/configure-aws-credentials step"
  value       = aws_iam_role.github_actions.arn
}
