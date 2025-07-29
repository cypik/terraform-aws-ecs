provider "aws" {
  region = local.region
}

locals {
  region         = "eu-west-1"
  name           = "test-ecs"
  environment    = "qa"
  container_name = "ecs-sample"
  container_port = 80
  tags = {
    Name    = local.name
    Example = local.name
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
  version            = "1.0.5"
  name               = local.name
  environment        = local.environment
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  type               = "public"
  vpc_id             = module.vpc.vpc_id
  cidr_block         = module.vpc.vpc_cidr_block
  igw_id             = module.vpc.igw_id
}

module "security_group" {
  source      = "cypik/security-group/aws"
  version     = "1.0.3"
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

################################################################################
# Cluster
################################################################################

module "ecs_cluster" {
  source = "../../modules/cluster"

  name = local.name

  # Capacity provider - autoscaling groups
  default_capacity_provider_use_fargate = false
  autoscaling_capacity_providers = {
    # On-demand instances
    ex11 = {
      auto_scaling_group_arn         = module.autoscaling["on_demand"].autoscaling_group_arn
      managed_termination_protection = "ENABLED"

      managed_scaling = {
        maximum_scaling_step_size = 5
        minimum_scaling_step_size = 1
        status                    = "ENABLED"
        target_capacity           = 60
      }

      default_capacity_provider_strategy = {
        weight = 60
        base   = 20
      }
    }
    # # Spot instances
    # ex2 = {
    #   auto_scaling_group_arn         = module.autoscaling["spot"].autoscaling_group_arn
    #   managed_termination_protection = "ENABLED"
    #
    #   managed_scaling = {
    #     maximum_scaling_step_size = 5
    #     minimum_scaling_step_size = 1
    #     status                    = "ENABLED"
    #     target_capacity           = 90
    #   }
    #
    #   default_capacity_provider_strategy = {
    #     weight = 40
    #   }
    # }
  }

}

###############################################################################
###Service
###############################################################################


module "ecs_service" {
  source = "./../.."

  create_cluster = false
  cluster_arn    = module.ecs_cluster.arn

  ##service1
  services = {
    ecsdemo97 = {
      # Task Definition
      cpu                      = 256
      memory                   = 512
      desired_count            = 1
      requires_compatibilities = ["EC2"]
      capacity_provider_strategy = {
        # Spot instances
        spot = {
          capacity_provider = module.ecs_cluster.autoscaling_capacity_providers["ex_1"].name
          weight            = 1
          base              = 1
        }
      }
      volume = {
        my-vol = {
          host_path = "/ecs/my-vol-data"
        }
      }

      # Container definition(s)
      container_definitions = {
        (local.container_name) = {
          image = "httpd:2.4"
          port_mappings = [
            {
              name          = local.container_name
              containerPort = local.container_port
              protocol      = "tcp"
            }
          ]

          mount_points = [
            {
              sourceVolume  = "my-vol",
              containerPath = "/usr/local/apache2/htdocs/"
            }
          ]

          entry_point = ["httpd-foreground"]

          # Example image used requires access to write to root filesystem
          readonly_root_filesystem = false

        }
      }
      load_balancer = {
        service = {
          target_group_arn = module.lb.target_group_arns[0]
          container_name   = local.container_name
          container_port   = local.container_port
        }
      }

      subnet_ids = module.subnets.private_subnet_id
      security_group_rules = {
        alb_ingress = {
          type                     = "ingress"
          from_port                = local.container_port
          to_port                  = local.container_port
          protocol                 = "tcp"
          description              = "Service port"
          source_security_group_id = module.lb.security_group_id
        }
      }
    },
  }

}


################################################################################
# Supporting Resources
################################################################################

# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html#ecs-optimized-ami-linux
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended"
}


module "autoscaling" {
  source = "cypik/ec2-autoscaling/aws"

  for_each = {
    # On-demand instances
    on_demand = {
      instance_type              = "t2.micro"
      use_mixed_instances_policy = false
      mixed_instances_policy     = {}
      user_data                  = <<-EOT
        #!/bin/bash

        cat <<'EOF' >> /etc/ecs/ecs.config
        ECS_CLUSTER=${local.name}
        ECS_LOGLEVEL=debug
        ECS_CONTAINER_INSTANCE_TAGS=${jsonencode(local.tags)}
        ECS_ENABLE_TASK_IAM_ROLE=true
        EOF
      EOT
    }
    # Spot instances
    spot = {
      instance_type              = "t2.medium"
      use_mixed_instances_policy = true
      mixed_instances_policy = {
        instances_distribution = {
          on_demand_base_capacity                  = 0
          on_demand_percentage_above_base_capacity = 0
          spot_allocation_strategy                 = "price-capacity-optimized"
        }

        override = [
          {
            instance_type     = "t3.medium"
            weighted_capacity = "1"
          },
        ]
      }
      user_data = <<-EOT
        #!/bin/bash

        cat <<'EOF' >> /etc/ecs/ecs.config
        ECS_CLUSTER=${local.name}
        ECS_LOGLEVEL=debug
        ECS_CONTAINER_INSTANCE_TAGS=${jsonencode(local.tags)}
        ECS_ENABLE_TASK_IAM_ROLE=true
        ECS_ENABLE_SPOT_INSTANCE_DRAINING=true
        EOF
      EOT
    }
  }

  #  network_interfaces = [
  #    {
  #      associate_public_ip_address = true                               # Assign public IP
  #      subnet_id                   = module.subnets.public_subnet_id[0] # Assign to a public subnet
  #    }
  #  ]
  name = "${local.name}-${each.key}"

  image_id      = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
  instance_type = each.value.instance_type

  security_groups                 = [module.security_group.security_group_id]
  user_data                       = base64encode(each.value.user_data)
  ignore_desired_capacity_changes = true

  create_iam_instance_profile = true
  iam_role_name               = local.name
  iam_role_description        = "ECS role for ${local.name}"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  vpc_zone_identifier = module.subnets.private_subnet_id
  health_check_type   = "EC2"
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1

  # https://github.com/hashicorp/terraform-provider-aws/issues/12582
  autoscaling_group_tags = {
    AmazonECSManaged = true
  }

  # Required for  managed_termination_protection = "ENABLED"
  protect_from_scale_in = true

  # Spot instances
  use_mixed_instances_policy = each.value.use_mixed_instances_policy
  mixed_instances_policy     = each.value.mixed_instances_policy

  tags = local.tags
}

module "alb" {
  source  = "cypik/lb/aws"
  version = "1.0.2"
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