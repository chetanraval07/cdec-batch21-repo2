terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.26.0"
    }
  }

  backend "s3" {
    bucket  = "jenkins-bucxx"
    key     = "terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }
}

# 👇 provider MUST be OUTSIDE terraform block
provider "aws" {
  region = "eu-west-1"
}

#################################

data "aws_vpc" "default" {
  default = true
}

variable "cluster_name" {
  type    = string
  default = "my-cluster-19"
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

#################################
# IAM ROLE FOR EKS CLUSTER
#################################

resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

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

#################################
# IAM ROLE FOR NODE GROUP
#################################

resource "aws_iam_role" "node_role" {
  name = "eks-node-role"

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
  role  = aws_iam_role.node_role.name

  policy_arn = element([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ], count.index)
}

#################################
# EKS CLUSTER
#################################

resource "aws_eks_cluster" "mycluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = data.aws_subnets.default.ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

#################################
# NODE GROUP
#################################

resource "aws_eks_node_group" "nodegroup" {
  cluster_name    = aws_eks_cluster.mycluster.name
  node_group_name = "myb19-node-group"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = data.aws_subnets.default.ids

  instance_types = ["c7i-flex.large"]

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_policies
  ]
}

#################################
# OUTPUTS
#################################

output "cluster_name" {
  value = aws_eks_cluster.mycluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.mycluster.endpoint
}
