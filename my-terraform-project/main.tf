# 1_section
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # section 9 
  backend "s3" {
    bucket         = "abhishek-tf-state-storage"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform_lock"
  }
}




provider "aws" {
  region = "ap-south-1"
}

resource "aws_vpc" "my_new_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "terraform-vpc"
  }
}

# 2_section

# public subnet 
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.my_new_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "public_subnet"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.my_new_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "public_subnet_2"
  }
}

#private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.my_new_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "private_subnet"
  }

}

# 3_section
# internet Gateway 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_new_vpc.id

  tags = {
    Name = "igw"
  }
}

# public route table 
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_new_vpc.id

  tags = {
    Name = "public-rt"
  }
}

# Route to internet
resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# associate Route table with public subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# section 4 
# ALB security group 
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = " Allow HTTP from the internet"
  vpc_id      = aws_vpc.my_new_vpc.id

  ingress {
    description = "HTTP from Internet"
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

  tags = {
    Name = "alb_sg"
  }

}
# section 5
#  EC2 security group

resource "aws_security_group" "ec2_sg" {
  name        = "ec2_security_group"
  description = "Allow traffic only from ALB"
  vpc_id      = aws_vpc.my_new_vpc.id

  ingress {
    description     = "only from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Kubernetes Management traffic coming from your Laptop/GitHub Actions
  ingress {
    description = "Kubernetes API Server access"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allows deployment commands to reach K3s
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2_sg"
  }
}

#section 6
#create target group

resource "aws_lb_target_group" "tg" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_new_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "tg"
  }

}

# section 7
resource "aws_lb" "alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]

  subnets = [
    aws_subnet.public_subnet.id,
    aws_subnet.public_subnet_2.id
  ]


  tags = {
    Name = "my_alb"
  }
}


resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}


resource "aws_launch_template" "lt" {
  name_prefix   = "my-app-template"
  image_id      = "ami-0cc9838aa7ab1dce7"
  instance_type = "t3.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash

              # 1. Install necessary software
              yum update -y
              yum install docker amazon-cloudwatch-agent -y
              yum install aws-cli -y

              # section 13 kubernetes
              # . Allocate 2GB Virtual Swap Space on Disk to prevent 1GB RAM Instance Crashes
              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # 3. Install Lightweight Kubernetes (K3s)
              curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -


              # 2. Create CloudWatch Agent config FIRST
              # We do this early so we can monitor the startup process
              cat << 'CWCONFIG' > /opt/aws/amazon-cloudwatch-agent/bin/config.json
              {
                "logs": {
                  "logs_collected": {
                    "files": {
                      "collect_list": [
                        {
                          "file_path": "/var/log/messages",
                          "log_group_name": "ec2-system-logs",
                          "log_stream_name": "{instance_id}"
                        }
                      ]
                    }
                  }
                },
                "metrics": {
                  "append_dimensions": {
                    "InstanceId": "$${aws:InstanceId}"
                  },
                  "metrics_collected": {
                    "mem": {
                      "measurement": ["mem_used_percent"],
                      "metrics_collection_interval": 60
                    },
                    "disk": {
                      "measurement": ["used_percent"],
                      "resources": ["*"],
                      "metrics_collection_interval": 60
                    }
                  }
                }
              }
              CWCONFIG

              # 3. Start CloudWatch Agent
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
              -a fetch-config -m ec2 -s \
              -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json

              # 4. Start & enable Docker
              systemctl start docker
              systemctl enable docker
              
              # 5. Deploy the Application
              # Login to ECR 
              # aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin 095055159123.dkr.ecr.ap-south-1.amazonaws.com
             
              # pull image from ECR 
              # docker pull 095055159123.dkr.ecr.ap-south-1.amazonaws.com/producation-app:latest

              # Remove old container if exists
              # docker rm -f my-app || true
             
              # Run application Conainer 
              # docker run -d -p 80:3000 --name my-app \
              # 095055159123.dkr.ecr.ap-south-1.amazonaws.com/producation-app:latest

              EOF
  )
  # git push need 
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "my-app-instance"
    }
  }
}

# section 8
# ASG creation 
resource "aws_autoscaling_group" "aws_asg" {
  desired_capacity = 0
  max_size         = 0
  min_size         = 0

  vpc_zone_identifier = [
    aws_subnet.public_subnet.id,
    aws_subnet.public_subnet_2.id
  ]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.tg.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 600

  instance_refresh {
    strategy = "Rolling"
  }
  # top right 
  tag {
    key                 = "Name"
    value               = "my-asg-instance"
    propagate_at_launch = true
  }
}

# section 14 output
output "app_url" {
  value       = "http://${aws_lb.alb.dns_name}"
  description = "Copy and paste this into your browser to see your app"
}

output "asg_name" {
  value       = aws_autoscaling_group.aws_asg.name
  description = "The name of the running Auto Scaling Group"
}

# section 9
# cloud watch Monitoring 

resource "aws_sns_topic" "alerts" {
  name = "devops-alerts"
}

resource "aws_sns_topic_subscription" "email_msg" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "monbiju157@gmail.com"
}

#cpu alarm

resource "aws_cloudwatch_metric_alarm" "high_aws" {
  alarm_name          = "high-cpu-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    AutoScalingGroup = aws_autoscaling_group.aws_asg.name

  }

  alarm_description = "This alarm monitors EC2 CPU usa"

  alarm_actions = [aws_sns_topic.alerts.arn]

}

# section 10 
# cloud watch agent 
resource "aws_iam_role" "ec2_cloudwatch_role" {
  name = "ec2_cloudwatch_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Permission 1: Allow EC2 to send logs to CloudWatch
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Permission 2: Allow EC2 to pull your Docker image from ECR
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Permission 3: ALLow to SSM 
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#permission 4: aws readonly-policy for grafana setup 
# Attaches the AWS-managed ReadOnly policy to your existing EC2 IAM Role
resource "aws_iam_role_policy_attachment" "grafana_cloudwatch_read" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_cloudwatch_profile"
  role = aws_iam_role.ec2_cloudwatch_role.name
}

resource "aws_cloudwatch_log_group" "system_logs" {
  name              = "ec2-system-logs"
  retention_in_days = 3
}

# section 11
# aws ecr 
resource "aws_ecr_repository" "producation_app_repo" {
  name = "producation-app"

  image_scanning_configuration {
    scan_on_push = true
  }

  image_tag_mutability = "MUTABLE"

  tags = {
    Name = "producation-app-repo"
  }
}
