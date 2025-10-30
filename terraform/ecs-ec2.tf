# ECS EC2集群配置 (支持FUSE)
# 如果Fargate不支持FUSE，可以使用这个配置

# EC2启动模板
resource "aws_launch_template" "ecs_ec2" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t3.medium"

  vpc_security_group_ids = [aws_security_group.ecs_ec2.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_ec2.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    cluster_name = aws_ecs_cluster.main.name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-ecs-instance"
    }
  }
}

# ECS优化AMI
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# EC2实例角色
resource "aws_iam_role" "ecs_ec2_role" {
  name = "${var.project_name}-ec2-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_role_policy" {
  role       = aws_iam_role.ecs_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_ec2" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ecs_ec2_role.name
}

# EC2安全组
resource "aws_security_group" "ecs_ec2" {
  name_prefix = "${var.project_name}-ec2-sg"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 32768
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "ecs_ec2" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = var.subnet_ids
  # target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"

  min_size         = 1
  max_size         = 3
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.ecs_ec2.id
    version = "$Latest"
  }

  # 启用实例保护以支持托管终止保护
  protect_from_scale_in = false

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }
}

# ECS容量提供者
resource "aws_ecs_capacity_provider" "ec2" {
  name = "cp-${var.project_name}"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_ec2.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      status          = "ENABLED"
      target_capacity = 80
    }
  }
}

# 更新ECS集群以支持EC2
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ec2.name
  }
}
