include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "tfr:///terraform-aws-modules/eks/aws?version=20.0.0"
}

dependency "vpc" {
  config_path = "../vpc"
}

inputs = {
  cluster_name    = "devops-lab-main"
  cluster_version = "1.28"
  vpc_id          = dependency.vpc.outputs.vpc_id
  subnet_ids      = dependency.vpc.outputs.private_subnets

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 2
      desired_size = 1
      instance_types = ["t3.medium"]
    }
  }
}
