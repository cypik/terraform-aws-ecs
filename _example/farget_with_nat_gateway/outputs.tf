################################################################################
# Cluster
################################################################################

output "cluster_arn" {
  description = "ARN that identifies the cluster"
  value       = module.ecs.cluster_arn
}

output "cluster_id" {
  description = "ID that identifies the cluster"
  value       = module.ecs.cluster_id
}

output "cluster_name" {
  description = "Name that identifies the cluster"
  value       = module.ecs.cluster_name
}

output "cluster_capacity_providers" {
  description = "Map of cluster capacity providers attributes"
  value       = module.ecs.cluster_capacity_providers
}

output "cluster_autoscaling_capacity_providers" {
  description = "Map of capacity providers created and their attributes"
  value       = module.ecs.autoscaling_capacity_providers
}

output "service_iam_role_name" {
  description = "Service IAM role name"
  value       = module.ecs.task_exec_iam_role_name
}

output "service_iam_role_arn" {
  description = "Service IAM role ARN"
  value       = module.ecs.task_exec_iam_role_arn
}

output "service_iam_role_unique_id" {
  description = "Stable and unique string identifying the service IAM role"
  value       = module.ecs.task_exec_iam_role_unique_id
}

output "service_id" {
  description = "ARN that identifies the service"
  value       = module.ecs.services
}
