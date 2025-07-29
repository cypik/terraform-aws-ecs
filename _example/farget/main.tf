provider "aws" {
  region = local.region
}

locals {
  region         = "eu-west-2"
  name           = "test"
  environment    = "demo"
  container_name = "apache"
  container_port = 80
  tags = {
    Name = local.name
  }
}


module "vpc" {
  source      = "cypik/vpc/aws"
  version     = "1.0.3"
  name        = local.name
  environment = local.environment
  cidr_block  = "10.0.0.0/16"
}

module "subnets" {
  source             = "cypik/subnet/aws"
  version            = "1.0.2"
  name               = local.name
  environment        = local.environment
  availability_zones = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  type               = "public"
  vpc_id             = module.vpc.vpc_id
  cidr_block         = module.vpc.vpc_cidr_block
  igw_id             = module.vpc.igw_id
}


module "security_group" {
  source      = "cypik/security-group/aws"
  version     = "1.0.1"
  name        = local.name
  environment = local.environment
  vpc_id      = module.vpc.vpc_id

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

module "ecs" {
  source = "../.."

  name        = local.name
  environment = local.environment
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
    ecsdemo-frontend2 = { ## service name
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

          readonly_root_filesystem = false
        },
      }
      service_connect_configuration = {
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

      tasks_iam_role_statements = [
        {
          actions   = ["s3:List*"]
          resources = ["arn:aws:s3:::*"]
        }
      ]

      assign_public_ip = true
      subnet_ids       = module.subnets.public_subnet_id
      security_group_rules = {
        alb_ingress = {
          type                     = "ingress"
          from_port                = local.container_port
          to_port                  = local.container_port
          protocol                 = "tcp"
          description              = "Service port"
          source_security_group_id = module.alb.security_group_id
        }
      }
    },
  }

  tags = local.tags
}




module "alb" {
  source  = "cypik/lb/aws"
  version = "1.0.4"
  name    = "${local.name}-lb"

  load_balancer_type = "application"
  subnets            = module.subnets.public_subnet_id
  vpc_id             = module.vpc.vpc_id
  allowed_ip         = ["0.0.0.0/0"]
  allowed_ports      = [80]
  https_enabled      = false
  http_enabled       = true
  https_port         = 443
  http_listener_type = "forward"
  target_group_port  = 80

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "TCP"
      target_group_index = 0
    },
  ]
  #  https_listeners = [
  #    {
  #      port               = 443
  #      protocol           = "TLS"
  #      target_group_index = 0
  #      certificate_arn    = ""
  #    },
  ##    {
  ##      port               = 84
  ##      protocol           = "TLS"
  ##      target_group_index = 0
  ##      certificate_arn    = ""
  ##    },
  #  ]

  target_groups = [
    {
      backend_protocol     = "HTTP"
      backend_port         = 80
      target_type          = "ip"
      deregistration_delay = 300
      health_check = {
        enabled             = true
        target_type         = "ip"
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 10
        protocol            = "HTTP"
        matcher             = "200-399"
      }

    }
  ]
}