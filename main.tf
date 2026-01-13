########################################
# Provider
########################################
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket         = "jenkins-bucxx"
    key            = "infra/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

########################################
# Variables
########################################
variable "region" {
  default = "eu-west-1"
}

variable "cluster_name" {
  default = "my-cluster-19"
}

variable "node_group_name" {
  default = "myb19-node-group"
}

########################################
# Data Sources (Use existing VPC)
########################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

########################################
# IAM Role – EKS Cluster
########################################
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

########################################
# IAM Role – Worker Nodes
########################################
resource "aws_iam_role" "node_role" {
  name = "eks-node-role-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  count = 3

  role = aws_iam_role.node_role.name

  policy_arn = element([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ], count.index)
}

########################################
# EKS Cluster
########################################
resource "aws_eks_cluster" "mycluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = data.aws_subnets.default.ids
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

########################################
# EKS Node Group
########################################
resource "aws_eks_node_group" "nodegroup" {
  cluster_name    = aws_eks_cluster.mycluster.name
  node_group_name = var.node_group_name
  node_role_arn  = aws_iam_role.node_role.arn
  subnet_ids     = data.aws_subnets.default.ids

  instance_types = ["c7i-flex.large"]

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  depends_on = [
    aws_eks_cluster.mycluster,
    aws_iam_role_policy_attachment.node_policies
  ]
}

########################################
# Outputs
########################################
output "cluster_name" {
  value = aws_eks_cluster.mycluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.mycluster.endpoint
}
