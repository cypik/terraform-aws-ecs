provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {}

terraform {
  backend "s3" {
    bucket = "terraform-s3-testing-ecs"
    key    = "env/testing"
    region = "eu-west-1"
  }
}

locals {
  region         = "eu-west-1"
  name           = "test-ecs"
  vpc_cidr       = "10.0.0.0/16"
  container_name = "apache"
  container_port = 80
  tags = {
    Name = local.name
  }
}


module "vpc" {
  source     = "cypik/vpc/aws"
  version    = "1.0.1"
  name       = local.name
  cidr_block = "10.0.0.0/16"
}

module "subnets" {
  source              = "cypik/subnet/aws"
  version             = "1.0.2"
  nat_gateway_enabled = true
  single_nat_gateway  = true
  availability_zones  = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  vpc_id              = module.vpc.id
  type                = "public-private"
  igw_id              = module.vpc.igw_id
  cidr_block          = module.vpc.vpc_cidr_block
}


module "security_group" {
  source  = "cypik/security-group/aws"
  version = "1.0.1"
  name    = local.name
  vpc_id  = module.vpc.id

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
  source = "../"

  cluster_name = local.name

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
      cpu                      = 1024
      memory                   = 4096
      desired_count            = 2
      autoscaling_min_capacity = 2
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

      subnet_ids = module.subnets.private_subnet_id
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

    ##service1
    ecs-demo2 = {
      cpu                      = 1024
      memory                   = 4096
      desired_count            = 2
      autoscaling_min_capacity = 2
      autoscaling_max_capacity = 5 # Container definition(s)
      container_definitions = {
        "nginx81" = {
          image = "themaheshyadav/nginx81:latest"
          port_mappings = [
            {
              name          = "nginx81"
              containerPort = 81
              protocol      = "tcp"
            }
          ]
          # Example image used requires access to write to root filesystem
          readonly_root_filesystem = false
        },

        "nginx82" = {
          image = "themaheshyadav/nginx82:latest"
          port_mappings = [
            {
              name          = "nginx82"
              containerPort = 82
              protocol      = "tcp"
            }
          ]

          # Example image used requires access to write to root filesystem
          readonly_root_filesystem = false
        },
      }

      load_balancer = {
        grafana = {
          target_group_arn = module.alb.target_group_arns[1]
          container_name   = "nginx81"
          container_port   = 81
        },
        nginx82 = {
          target_group_arn = module.alb.target_group_arns[2]
          container_name   = "nginx82"
          container_port   = 82
        }
      }

      tasks_iam_role_name        = "${local.name}-tasks2"
      tasks_iam_role_description = "Example tasks IAM role2 for ${local.name}-2"
      tasks_iam_role_policies = {
        ReadOnlyAccess = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      }
      tasks_iam_role_statements = [
        {
          actions   = ["s3:List*"]
          resources = ["arn:aws:s3:::*"]
        }
      ]

      subnet_ids = module.subnets.private_subnet_id
      security_group_rules = {
        alb_ingress = {
          type                     = "ingress"
          from_port                = 81
          to_port                  = 82
          protocol                 = "tcp"
          description              = "Service port"
          source_security_group_id = module.alb.security_group_id
        },
        egress_all = {
          type        = "egress"
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_blocks = ["0.0.0.0/0"]
        }
      }
    }
  }

  tags = local.tags
}


###############################################################################
###Service
###############################################################################

resource "aws_service_discovery_http_namespace" "this" {
  name        = local.name
  description = "CloudMap namespace for ${local.name}"
  tags        = local.tags
}

module "alb" {
  source = "./../modules/alb"

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
    {
      port               = 81
      protocol           = "HTTP"
      target_group_index = 1
    },
    {
      port               = 82
      protocol           = "HTTP"
      target_group_index = 2
    }
  ]

  target_groups = [
    {
      name             = local.name
      backend_protocol = "HTTP"
      backend_port     = local.container_port
      target_type      = "ip"
    },
    {
      name             = "nginx81"
      backend_protocol = "HTTP"
      backend_port     = 81
      target_type      = "ip"
    },
    {
      name             = "nginx82"
      backend_protocol = "HTTP"
      backend_port     = 82
      target_type      = "ip"
    }
  ]

  tags = local.tags
}