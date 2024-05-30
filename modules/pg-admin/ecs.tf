data "aws_ssm_parameter" "latest-ecs-amazon-ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

data "aws_ami" "latest-ecs-amazon-linux" {
  owners = ["amazon"]
  filter {
    name   = "image-id"
    values = [data.aws_ssm_parameter.latest-ecs-amazon-ami.value]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ecs_task_definition" "pg-admin-task-def" {
  task_definition = var.env
  depends_on = [
    aws_ecs_task_definition.pg-admin
  ]
}

data "aws_db_instance" "pg-rds" {
  db_instance_identifier = aws_db_instance.pg_rds.identifier
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [aws_vpc.project_vpc.id]
  }
  depends_on = [
    aws_subnet.private,
    aws_subnet.public
  ]

  tags = {
    Tier = "Public"
  }
}

# Cluster for pg-admin.
resource "aws_ecs_cluster" "pg-admin-cluster" {
  name = "${var.env}-pg-admin-cluster"

  tags = {
    Name        = "${var.env}-pg-admin-cluster"
    Environment = var.env
    Service     = "pg-admin"
  }
}

# Laucnh configuration for pg-admin.
resource "aws_launch_template" "pg-admin-lt" {
  name          = "lt-pgadmin${var.env}"
  image_id      = data.aws_ami.latest-ecs-amazon-linux.id
  instance_type = var.web_instance_type
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_sg.id]

  }
  user_data = base64encode(templatefile("./modules/pg-admin/templates/launch_configuration.sh", {
    ECS_CLUSTER = aws_ecs_cluster.pg-admin-cluster.name
    SERVER_CONFIG = templatefile("./modules/pg-admin/templates/servers.json", {
      PROJECT     = var.project
      ENV         = var.env
      HOST        = data.aws_db_instance.pg-rds.address
      DB_NAME     = var.db_name
      DB_USERNAME = var.db_username
      }
    )
    }
    )
  )
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_agent.name
  }
  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
      volume_size = 20
    }
  }
}

# ALG for pg-admin.
resource "aws_autoscaling_group" "pg-admin-asg" {
  name                      = "pg-admin-${var.env}"
  max_size                  = 2
  min_size                  = 2
  health_check_grace_period = 180
  desired_capacity          = 2
  force_delete              = true
  launch_template {
    id      = aws_launch_template.pg-admin-lt.id
    version = "$Latest"
  }
  vpc_zone_identifier = tolist(data.aws_subnets.public.ids)
  target_group_arns   = [aws_alb_target_group.pg-admin.arn]

  tag {
    key                 = "Environment"
    value               = var.env
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "pg-admin"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

}

# Generate password for pg-admin.
resource "random_password" "pg_admin_pass" {
  length           = 40
  special          = true
  min_special      = 5
  override_special = "!#$%^&*()-_=+[]{}<>:?"
  keepers = {
    pass_version = 1
  }
}

# create SSM parameter store with generated password.
resource "aws_ssm_parameter" "pg_admin_pass" {
  name        = "/${var.env}/pg_admin/password/admin"
  description = "pg admin password for ${var.route53_zone}-${var.env}"
  type        = "SecureString"
  value       = random_password.pg_admin_pass.result

  tags = {
    environment = var.env
  }
}

// # Generate pg-admin config file with RDS endpoint, username, project name and database name.
// # After that we dont have to set it up manually in GUI.
// data "templatefile" "pg-admin-server-config" {

//   template = file("./modules/pg-admin/templates/servers.json")
//   vars = {
//     PROJECT     = "${var.project}"
//     ENV         = "${var.env}"
//     HOST        = "${data.aws_db_instance.pg-rds.address}"
//     DB_NAME     = "${var.db_name}"
//     DB_USERNAME = "${var.db_username}"
//   }
// }


# Create task definitions from generated data.
resource "aws_ecs_task_definition" "pg-admin" {
  family             = var.env
  execution_role_arn = "arn:aws:iam::198464718186:role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS"
  network_mode       = "bridge"
  volume {
    name      = "configs"
    host_path = "/mnt/configs"
  }

  container_definitions = templatefile("./modules/pg-admin/templates/pg-admin-td.json", {
    PGADMIN_DEFAULT_EMAIL = var.pg_admin_email
    PARAMETER_STORE_ARN   = aws_ssm_parameter.pg_admin_pass.arn
    }
  )


  tags = {
    ResourceGroup = "Terraform"
    Environment   = var.env
    Service       = "pg-admin"
  }
}

# Create ECS service for pg-admin. 
resource "aws_ecs_service" "pg-admin" {
  name            = "pg-admin"
  cluster         = aws_ecs_cluster.pg-admin-cluster.name
  task_definition = "${aws_ecs_task_definition.pg-admin.family}:${max(aws_ecs_task_definition.pg-admin.revision, data.aws_ecs_task_definition.pg-admin-task-def.revision)}"
  launch_type     = "EC2"
  # DAEMON used to be sure that each node will have one task.
  scheduling_strategy = "DAEMON"
}
