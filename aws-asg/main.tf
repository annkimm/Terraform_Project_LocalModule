resource "aws_launch_configuration" "aws_asg_launch" {
  image_id        = "ami-0ea4d4b8dc1e46212"
  instance_type   = var.instance_type
  security_groups = [var.SSH_SG_ID, var.HTTP_HTTPS_SG_ID]
  key_name = "EC2-key"

  user_data = <<-EOF
    #!/bin/bash
    sudo yum -y update
    sudo yum -y install httpd.x86_64
    sudo systemctl start httpd.service
    sudo systemctl enable httpd.service
    echo "<h1>Hello My WEB</h1>" > /var/www/html/index.html
  EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "aws_asg" {
  name                 = "${var.name}-${aws_launch_configuration.aws_asg_launch.name}"
  launch_configuration = aws_launch_configuration.aws_asg_launch.name
  min_size             = var.min_size
  max_size             = var.max_size
  desired_capacity = var.desired_capacity
  vpc_zone_identifier  = var.private_subnets

  target_group_arns = [var.target_group_arns]
  health_check_type = "ELB"

  lifecycle {
    create_before_destroy = true
  }

  # 교체용 ASG 배포 완료를 고려하기 전 최소 인스턴스 수 만큼 상태검사를 통과할 때까지 대기 후 배포완료
  min_elb_capacity  = var.min_size

  tag {
    key                 = "Name"
    value               = "${var.name}-Terraform_Instance"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "aws-asg-scaling-out-policy" {
  name                   = "aws-asg-scaling-out-policy"
  scaling_adjustment     = 4
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.aws_asg.name
}

resource "aws_cloudwatch_metric_alarm" "aws-asg-max-alerm" {
  alarm_name          = "aws-asg-max-alerm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.aws_asg.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.aws-asg-scaling-out-policy.arn]
}

resource "aws_autoscaling_policy" "aws-asg-scaling-in-policy" {
  name                   = "aws-asg-scaling-in-policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.aws_asg.name
}

resource "aws_cloudwatch_metric_alarm" "aws-asg-min-alerm" {
  alarm_name          = "aws-asg-min-alerm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 10

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.aws_asg.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.aws-asg-scaling-in-policy.arn]
}