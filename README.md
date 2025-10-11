# EKS Terraform Infrastructure Guide

This project automates the creation of an Amazon EKS (Elastic Kubernetes Service) cluster with autoscaling, load balancing, and persistent storage using Terraform.

# 📌 What This Code Creates

**EKS Cluster:** Managed Kubernetes control plane

**Worker Nodes:** EC2 instances to run your applications

**Karpenter:** Automatically scales nodes based on demand

**AWS Load Balancer Controller:** Manages external traffic to your apps

**EFS Storage:** Shared file system accessible by multiple pods

**VPC & Subnets:** Secure network isolation

**IAM Roles & Policies:** Proper access management

You can use this cluster to deploy containerized applications with high availability and persistent storage.

# 🔧 Prerequisites

**1. Software**
- AWS CLI (v2)
- Terraform (v1.0+)
- kubectl
  
**2. AWS Account**
Admin access with a configured AWS CLI profile (example: tf-admin)

**3. Configure AWS CLI**
aws configure --profile tf-admin
#Enter Access Key, Secret Key, Default Region (e.g., ap-south-1), and Output (json)

# 📁 File Structure Overview and Purpose

terraform-eks/

├── envs/dev.tfvars                   

├── backend-config/dev.tfbackend        

├── eks.tf                               

├── vpc.tf                   

├── karpenter.tf             

├── alb-controller.tf        

├── efs.tf                  

├── ec2nodeclass.tf          

├── provider.tf             

├── output.tf                

├── app-efs.yaml             

└── setup-backend-fixed.sh  

**envs/dev.tfvars** – Stores environment-specific variables like region, cluster name, and node settings.

**backend-config/dev.tfbackend** – Configures Terraform backend for state storage and locking.

**eks.tf** – Creates the EKS cluster and managed node groups.

**vpc.tf** – Sets up VPC, subnets, gateways, and route tables.

**karpenter.tf** – Deploys Karpenter controller on eks for automatic node scaling.

**alb-controller.tf** – Installs AWS Load Balancer Controller on eks for traffic management.

**efs.tf** – Creates EFS file system and storage classes for persistent storage.

**ec2nodeclass.tf** – Defines node templates for Karpenter including instance types and sizes.

**provider.tf** – Configures the AWS provider for Terraform.

**variables.tf** – Declares all variables used across Terraform scripts.

**locals.tf** – Defines reusable local values for convenience.

**output.tf** – Specifies outputs like cluster endpoint, node info, and load balancer URL.

**app-efs.yaml** – Sample Kubernetes app that mounts EFS storage.

**setup-backend-fixed.sh** – Bootstrap script to create S3/DynamoDB and initialize Terraform.

**Edit envs/.tfvars to your scenario**

# 🚀 Deployment Steps

**1. Prepare Environment**

cd terraform-eks

chmod +x setup-backend-fixed.sh  # Linux/Mac only

aws sts get-caller-identity --profile tf-admin  # Verify credentials

**2. Run Bootstrap Script**

./setup-backend-fixed.sh --environment dev --region ap-south-1 --profile tf-admin

./setup-backend-fixed.sh --environment test --region ap-south-1 --profile tf-admin

**3. Review Config**

envs/.tfvars notepad # Update settings if needed

**4. Plan & Apply**

terraform plan -var-file="envs/dev.tfvars"  # Check what will be created

terraform apply -var-file="envs/dev.tfvars" # Deploy infrastructure

**5. Configure kubectl**

aws eks update-kubeconfig --region ap-south-1 --name dev-new-eks-karpenter --profile tf-admin

kubectl get nodes  # Verify cluster

**6. Deploy Sample Application**

kubectl apply -f app-efs.yaml  # Deploy sample app using EFS

kubectl get pods                # Check pod status

kubectl get services            # Check service

kubectl get ingress             # Get load balancer URL

**7. Monitor & Logs**

**Cluster metrics**

kubectl top nodes

kubectl top pods

**Karpenter logs**

kubectl logs -f -n dev-karpenter-namespace deployment/dev-karpenter

**Check all system pods**

kubectl get pods -n kube-system

**8. Cleanup**

**Delete Everything**

kubectl delete -f app-efs.yaml

terraform destroy -var-file="envs/dev.tfvars"
