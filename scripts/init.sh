#!/usr/bin/env bash
set -euo pipefail

# -------- required inputs --------
ACCOUNT_ID="745039059228"
AWS_REGION="eu-central-1"
PROJECT_NAME="surepay"
GITHUB_REPO_SLUG="mohammedrampurawala1111/tech-assesment" # Format: owner/repo (works for personal or org repos)
# Allow all refs and PR tokens by default; override with e.g. "repo:owner/repo:ref:refs/heads/main"
GITHUB_SUB_CONDITION="repo:${GITHUB_REPO_SLUG}:*"
TF_STATE_BUCKET="surepay-tf-state"  # adjust to your state bucket

# -------- derived names --------
OIDC_PROVIDER_URL="token.actions.githubusercontent.com"
OIDC_AUDIENCE="sts.amazonaws.com"

POLICY_NAME="${PROJECT_NAME}-github-oidc-policy"
ROLE_NAME="${PROJECT_NAME}-github-oidc-role"
POLICY_DOC_FILE="$(mktemp)"
TRUST_DOC_FILE="$(mktemp)"

echo "Using temp files:"
echo "  Policy doc: ${POLICY_DOC_FILE}"
echo "  Trust doc : ${TRUST_DOC_FILE}"

# Ensure Terraform state bucket exists
echo "Ensuring Terraform state bucket ${TF_STATE_BUCKET} exists..."
if aws s3api head-bucket --bucket "${TF_STATE_BUCKET}" >/dev/null 2>&1; then
  echo "Bucket ${TF_STATE_BUCKET} already exists."
else
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${TF_STATE_BUCKET}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket \
      --bucket "${TF_STATE_BUCKET}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  fi

  aws s3api put-bucket-versioning \
    --bucket "${TF_STATE_BUCKET}" \
    --versioning-configuration Status=Enabled

  aws s3api put-public-access-block \
    --bucket "${TF_STATE_BUCKET}" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  echo "Created and secured Terraform state bucket ${TF_STATE_BUCKET}."
fi

cat <<EOF > "${POLICY_DOC_FILE}"
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": [ "sts:AssumeRole" ], "Resource": "*" },
    { "Effect": "Allow", "Action": [ "ecr:GetAuthorizationToken" ], "Resource": "*" },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchDeleteImage",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:CreateRepository",
        "ecr:DeleteRepository",
        "ecr:DescribeImages",
        "ecr:DescribeRepositories",
        "ecr:GetLifecyclePolicy",
        "ecr:PutLifecyclePolicy",
        "ecr:DeleteLifecyclePolicy",
        "ecr:GetRepositoryPolicy",
        "ecr:SetRepositoryPolicy",
        "ecr:DeleteRepositoryPolicy",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:ListImages",
        "ecr:PutImage",
        "ecr:TagResource",
        "ecr:UntagResource",
        "ecr:ListTagsForResource",
        "ecr:UploadLayerPart"
      ],
      "Resource": "arn:aws:ecr:${AWS_REGION}:${ACCOUNT_ID}:repository/${PROJECT_NAME}-app"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:*",
        "codedeploy:*",
        "ec2:*",
        "elasticloadbalancing:*",
        "iam:GetRole",
        "iam:PassRole",
        "iam:ListRoles",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:CreateRole",
        "iam:UpdateRole",
        "iam:DeleteRole",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRoleTags"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DescribeLogGroups",
        "logs:GetLogEvents",
        "logs:FilterLogEvents",
        "logs:PutRetentionPolicy",
        "logs:DeleteLogGroup",
        "logs:ListTagsForResource",
        "logs:TagLogGroup",
        "logs:UntagLogGroup"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:DescribeAlarms",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarmHistory",
        "cloudwatch:ListTagsForResource",
        "cloudwatch:TagResource",
        "cloudwatch:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [ "s3:ListBucket", "s3:GetObject", "s3:PutObject" ],
      "Resource": [
        "arn:aws:s3:::${TF_STATE_BUCKET}",
        "arn:aws:s3:::${TF_STATE_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [ "s3:CreateBucket", "s3:ListBucket", "s3:GetObject", "s3:PutObject" ],
      "Resource": [
        "arn:aws:s3:::codedeploy-${AWS_REGION}-${ACCOUNT_ID}",
        "arn:aws:s3:::codedeploy-${AWS_REGION}-${ACCOUNT_ID}/*"
      ]
    }
  ]
}
EOF

cat <<EOF > "${TRUST_DOC_FILE}"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER_URL}:aud": "${OIDC_AUDIENCE}"
        },
        "StringLike": {
          "${OIDC_PROVIDER_URL}:sub": "${GITHUB_SUB_CONDITION}"
        }
      }
    }
  ]
}
EOF

echo "Ensuring IAM OIDC provider exists..."
if aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?Arn=='arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}'] | length(@)" --output text | grep -q '^1$'; then
  echo "OIDC provider already exists."
else
  aws iam create-open-id-connect-provider \
    --url "https://${OIDC_PROVIDER_URL}" \
    --client-id-list "${OIDC_AUDIENCE}" \
    --thumbprint-list "9e99a48a9960b14926bb7f3b02e22da0afd10c65"
  echo "Created OIDC provider."
fi

echo "Creating/updating IAM policy ${POLICY_NAME}..."
if POLICY_ARN=$(aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" --query 'Policy.Arn' --output text 2>/dev/null); then
  # IAM allows only 5 policy versions; delete oldest non-default versions until we have room
  VERSION_COUNT=$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" --query 'length(Versions)' --output text)
  if [ "${VERSION_COUNT}" -ge 5 ]; then
    VERSIONS=$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
    for VERSION in ${VERSIONS}; do
      echo "Deleting old policy version ${VERSION}..."
      aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "${VERSION}"
      VERSION_COUNT=$((VERSION_COUNT - 1))
      if [ "${VERSION_COUNT}" -lt 5 ]; then
        break
      fi
    done
  fi
  aws iam create-policy-version \
    --policy-arn "${POLICY_ARN}" \
    --policy-document file://"${POLICY_DOC_FILE}" \
    --set-as-default
  echo "Updated existing policy version."
else
  POLICY_ARN=$(aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document file://"${POLICY_DOC_FILE}" \
    --query 'Policy.Arn' --output text)
  echo "Created policy ${POLICY_ARN}."
fi

echo "Creating/updating IAM role ${ROLE_NAME}..."
if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  aws iam update-assume-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-document file://"${TRUST_DOC_FILE}"
  echo "Updated trust policy."
else
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document file://"${TRUST_DOC_FILE}"
  echo "Created role."
fi

aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${POLICY_ARN}" || true

echo
echo "ROLE ARN: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "Use this ARN in GitHub workflows with aws-actions/configure-aws-credentials@v4."
echo "Cleanup temp files..."
rm -f "${POLICY_DOC_FILE}" "${TRUST_DOC_FILE}"
echo "Done."