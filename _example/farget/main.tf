provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {}


locals {
  region         = "eu-west-1"
  name           = "test-ecs"
  environment    = "qa"
  vpc_cidr       = "10.0.0.0/16"
  container_name = "apache"
  container_port = 80
  namespace_name = ["ecsdemo-frontend", "ecsdemo-backend"]
  tags = {
    Name = local.name
  }
}


module "vpc" {
  source      = "cypik/vpc/aws"
  version     = "1.0.1"
  name        = local.name
  environment = local.environment
  cidr_block  = "10.0.0.0/16"
}

module "subnets" {
  source             = "cypik/subnet/aws"
  version            = "1.0.2"
  name               = local.name
  environment        = local.environment
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  type               = "public"
  vpc_id             = module.vpc.id
  cidr_block         = module.vpc.vpc_cidr_block
  igw_id             = module.vpc.igw_id
}


module "security_group" {
  source      = "cypik/security-group/aws"
  version     = "1.0.1"
  name        = local.name
  environment = local.environment
  vpc_id      = module.vpc.id

  ## INGRESS Rules
  new_sg_ingress_rules_with_cidr_blocks = [{
    rule_count  = 1
    from_port   = 80
    to_port     = 82
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow http traffic."
    },
  ]
  ## EGRESS Rules
  new_sg_egress_rules_with_cidr_blocks = [{
    rule_count  = 1
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow  outbound traffic."
    }

  ]
}
###############################################################################
##########Cluster
###############################################################################


module "ecs" {
  source = "../.."

  cluster_name   = local.name
  create_cluster = true
  # Capacity provider
  fargate_capacity_providers = {
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
  }

  ##service1
  services = {
    ecsdemo-frontend = {
      cpu                      = 256
      memory                   = 512
      desired_count            = 1
      autoscaling_min_capacity = 1
      autoscaling_max_capacity = 5
      # Container definition(s)
      container_definitions = {
        (local.container_name) = {
          image = "httpd:latest"
          port_mappings = [
            {
              name          = local.container_name
              containerPort = local.container_port
              protocol      = "tcp"
            }
          ]

          entry_point = ["/usr/sbin/apache2", "-D", "FOREGROUND"]

          # Example image used requires access to write to root filesystem
          readonly_root_filesystem = false
        },
      }
      service_connect_configuration = {
        namespace = aws_service_discovery_http_namespace.this[0].arn
        service = {
          client_alias = {
            port     = local.container_port
            dns_name = local.container_name
          }
          port_name      = local.container_name
          discovery_name = local.container_name
        }
      }
      load_balancer = {
        service = {
          target_group_arn = module.alb.target_group_arns[0]
          container_name   = local.container_name
          container_port   = local.container_port
        }
      }

      tasks_iam_role_name        = "${local.name}-tasks"
      tasks_iam_role_description = "Example tasks IAM role for ${local.name}"
      tasks_iam_role_policies = {
        ReadOnlyAccess = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      }
      tasks_iam_role_statements = [
        {
          actions   = ["s3:List*"]
          resources = ["arn:aws:s3:::*"]
        }
      ]

      assign_public_ip = true
      subnet_ids       = module.subnets.public_subnet_id
      security_group_rules = {
        alb_ingress_3000 = {
          type                     = "ingress"
          from_port                = local.container_port
          to_port                  = local.container_port
          protocol                 = "tcp"
          description              = "Service port"
          source_security_group_id = module.alb.security_group_id
        }
        egress_all = {
          type        = "egress"
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_blocks = ["0.0.0.0/0"]
        }
      }
    },
  }

  tags = local.tags
}


###############################################################################
###Service
###############################################################################

resource "aws_service_discovery_http_namespace" "this" {
  count       = length(local.namespace_name) > 0 ? length(local.namespace_name) : 0
  name        = local.namespace_name[count.index]
  description = "CloudMap namespace for ${local.namespace_name[count.index]}"
  tags        = local.tags
}

module "alb" {
  source = "../../modules/alb"

  name = "${local.name}-lb"

  load_balancer_type = "application"

  vpc_id          = module.vpc.id
  subnets         = module.subnets.public_subnet_id
  security_groups = [module.security_group.security_group_id]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    },
  ]

  target_groups = [
    {
      name             = local.name
      backend_protocol = "HTTP"
      backend_port     = local.container_port
      target_type      = "ip"
    },
  ]

  tags = local.tags
}