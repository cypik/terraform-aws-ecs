# Script README

# Table of Contents
- [Introduction]
- [Cluster Module]
- [Service Module]
- [Usage]

## Introduction

This script is designed to create and manage AWS ECS clusters and services using Terraform.
It provides a modular structure for defining clusters and services with various configurations.

## Cluster Module

The "cluster" module is responsible for defining and configuring an ECS cluster. It offers a variety of options:

- `cluster_name`: Name of the ECS cluster.
- `cluster_configuration`: Configuration settings for the cluster.
- `cluster_settings`: Additional settings for the cluster.
- `create_cloudwatch_log_group`: Create a CloudWatch log group.
- `cloudwatch_log_group_retention_in_days`: Retention period for CloudWatch logs.
- `default_capacity_provider_use_fargate`: Whether to use Fargate as the default capacity provider.
- `fargate_capacity_providers`: Capacity providers for Fargate.
- `autoscaling_capacity_providers`: Capacity providers for autoscaling.
- Task execution IAM role configuration.

## Service Module

The "service" module defines ECS services that run within the cluster. It offers options such as:

- `ignore_task_definition_changes`: Ignore changes in the task definition.
- `alarms`: Configure CloudWatch alarms.
- `capacity_provider_strategy`: Define capacity provider strategies.
- `deployment settings` and maximum/minimum healthy percentages.
- `Service IAM role` configuration.
- `Task definition` settings and configurations.
- `Autoscaling` settings and policies.
- `Security group` settings.
- Other ECS service configurations.

## Usage

To use this script:

1. Make sure you have Terraform installed.

2. Create your own `.tf` file (e.g., `main.tf`) and define variables for the cluster and services.

3. Modify the variables according to your requirements.

4. Run the following Terraform commands to apply the configuration:

   terraform init
   
   terraform validate
   
   terraform plan
   
   terraform apply
   
 -if we need remove this  services then we need to use this following command terraform destroy 
