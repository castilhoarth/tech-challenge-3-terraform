data "aws_caller_identity" "current" {}

# Role de Control Plan do EKS
resource "aws_iam_role" "eks_cluster" {
    name = "${var.cluster_name}-cluster-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Principal = { Service = "eks.amazonaws.com" }
        }]
    })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_Policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    role       = aws_iam_role.eks_cluster.name
}

# Role dos Node Groups (Workers)
resource "aws_iam_role" "eks_nodes" {
    name = "${var.cluster_name}-node-role"
    
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Principal = { Service = "ec2.amazonaws.com" }
        }]
    })
}

resource "aws_iam_role_policy_attachment" "worker_node_Policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    role       = aws_iam_role.eks_nodes.name
}

# Role utilizada pelos Jobs de migration
resource "aws_iam_role" "migration" {
  name = "${var.cluster_name}-migration-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
    }]
  })
}

# Permissão para ler os secrets dos bancos no AWS Secrets Manager
resource "aws_iam_policy" "migration_secrets" {
  name = "${var.cluster_name}-migration-secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = [
        "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:tech-challenge/rds-auth-*",
        "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:tech-challenge/rds-flag-*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "migration_secrets" {
  role       = aws_iam_role.migration.name
  policy_arn = aws_iam_policy.migration_secrets.arn
}