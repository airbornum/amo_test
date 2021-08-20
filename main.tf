# Create provider, region
provider "aws" {
  region = "us-central-1"
}

# Get subnets list
data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

# Find default vpc
data "aws_vpc" "default" {
  default = true
}

# Create ALB security group, allow http port
resource "aws_security_group" "alb" {
  name = "terraform-alb-security-group"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Creat EC2 security group, allow 8080 port
resource "aws_security_group" "instance" {
  name = "terraform-instance-security-group"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# create ALB
resource "aws_lb" "alb" {
  name               = "terraform-alb"
  load_balancer_type = "application"
  subnets            = data.aws_subnet_ids.default.ids
  security_groups    = [aws_security_group.alb.id]
}

# Create listener for ALB
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
}

# Create ALB listener rule to default path
resource "aws_lb_listener_rule" "asg-listener_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    field  = "path-pattern"
    values = ["*"]
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg-target-group.arn
  }
}

# Create target group for ASG, create health checks
resource "aws_lb_target_group" "asg-target-group" {
  name     = "terraform-aws-lb-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Create Autoscaling group with EC2 instances
resource "aws_autoscaling_group" "ubuntu-ec2" {
  launch_configuration = aws_launch_configuration.ubuntu-ec2.name
  vpc_zone_identifier  = data.aws_subnet_ids.default.ids

  # Create connectin between ASG и ALB with taget group ARN
  target_group_arns = [aws_lb_target_group.asg-target-group.arn]
  health_check_type = "ELB"

  min_size = 1
  max_size = 3

  tag {
    key                 = "Name"
    value               = "terraform-asg-ubuntu-ec2"
    propagate_at_launch = true
  }
}

# Create configuration for EC2 instances
resource "aws_launch_configuration" "ubuntu-ec2" {
  image_id        = "ami-0c55b159cbfafe1f0"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.instance.id]
  lifecycle {
    create_before_destroy = true
  }
}

# Create route 53 record in aws domain and connect to ALB
resource "aws_route53_record" "amo-test" {
  zone_id = aws_route53_zone.example_hosted_zone.zone_id
  name    = "amo-test"
  type    = "CNAME"
  ttl     = "60"
  records = [alb.restricted_access_lb.id]
}
