# Calculate success rate: (2XX requests) / (Total requests) * 100
# Alarm triggers if success rate < 99.5% for 2 consecutive minutes
resource "aws_cloudwatch_metric_alarm" "alb_success_rate" {
  alarm_name          = "${var.project_name}-alb-success-rate"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  threshold           = 99.5
  alarm_description   = "Alarm if ALB success rate drops below 99.5% for 2+ minutes - triggers ECS deployment rollback"
  treat_missing_data  = "notBreaching"
  datapoints_to_alarm = 2

  # Use MathExpression to calculate success rate percentage
  metric_query {
    id          = "e1"
    expression  = "(m1 / IF(m1+m2+m3==0,1,m1+m2+m3)) * 100"
    label       = "Success Rate (%)"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "HTTPCode_Target_2XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "HTTPCode_Target_4XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
      }
    }
  }

  metric_query {
    id = "m3"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
      }
    }
  }

  alarm_actions = []

  tags = local.common_tags
}
