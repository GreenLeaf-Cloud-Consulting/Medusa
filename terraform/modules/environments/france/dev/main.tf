data "aws_vpc" "default" {
  default = true
}

module "ec2_backend" {
  instance_name    = "france-backend-instance"
  source           = "../../../ec2-instance"
  ami              = "ami-0256daaa9dbc8ea3c"
  instance_type    = "t4g.small"
  environment      = "dev"
  allowed_ports    = [22, 80, 9000]
  region           = "eu-west-3"
  ssh_user         = "admin"
  ansible_playbook = "playbook.yml"
  use_elastic_ip   = true
}

module "ec2_frontend" {
  instance_name    = "france-frontend-instance"
  source           = "../../../ec2-instance"
  ami              = "ami-0256daaa9dbc8ea3c"
  instance_type    = "t4g.small"
  environment      = "dev"
  allowed_ports    = [22, 80, 443, 3000]
  region           = "eu-west-3"
  ssh_user         = "admin"
  ansible_playbook = "playbook-frontend.yml"
  backend_ip       = module.ec2_backend.instance_ip
  use_elastic_ip   = true
  
  depends_on = [module.ec2_backend]
}

output "backend_instance_ip" {
  value = module.ec2_backend.instance_ip
}

output "frontend_instance_ip" {
  value = module.ec2_frontend.instance_ip
}

output "backend_ssh_private_key" {
  value     = module.ec2_backend.ssh_private_key
  sensitive = true
}

output "frontend_ssh_private_key" {
  value     = module.ec2_frontend.ssh_private_key
  sensitive = true
}

# ===================================
# MONITORING: CloudWatch + Lambda + Discord
# ===================================

# Récupérer le secret Discord webhook
data "aws_secretsmanager_secret" "discord_webhook" {
  name = "france-dev-discord-webhook"
}

data "aws_secretsmanager_secret_version" "discord_webhook" {
  secret_id = data.aws_secretsmanager_secret.discord_webhook.id
}

# SNS Topic pour les alarmes
resource "aws_sns_topic" "cloudwatch_alarms" {
  name = "france-dev-cloudwatch-alarms"

  tags = {
    Environment = "dev"
    Purpose     = "CloudWatch alarms notifications"
  }
}

# IAM Role pour Lambda
resource "aws_iam_role" "lambda_discord_notifier" {
  name = "france-dev-lambda-discord-notifier"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Environment = "dev"
  }
}

# IAM Policy pour Lambda - Logs CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_discord_notifier.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM Policy pour Lambda - Accès Secrets Manager
resource "aws_iam_role_policy" "lambda_secrets" {
  name = "lambda-secrets-access"
  role = aws_iam_role.lambda_discord_notifier.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = data.aws_secretsmanager_secret.discord_webhook.arn
    }]
  })
}

# Créer l'archive ZIP du code Lambda
data "archive_file" "lambda_discord" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda/lambda_function.zip"
}

# Lambda Function
resource "aws_lambda_function" "discord_notifier" {
  filename         = data.archive_file.lambda_discord.output_path
  function_name    = "france-dev-discord-notifier"
  role            = aws_iam_role.lambda_discord_notifier.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_discord.output_base64sha256
  runtime         = "python3.11"
  timeout         = 30

  environment {
    variables = {
      DISCORD_WEBHOOK_SECRET_NAME = data.aws_secretsmanager_secret.discord_webhook.name
    }
  }

  tags = {
    Environment = "dev"
  }
}

# Permission pour SNS d'invoquer Lambda
resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.cloudwatch_alarms.arn
}

# Subscription SNS → Lambda
resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.cloudwatch_alarms.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_notifier.arn
}

# Alarme CloudWatch - CPU > 70%
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "france-dev-high-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1  # 1 période au lieu de 2 pour test rapide
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300  # 5 minutes
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Cette alarme se déclenche quand le CPU dépasse 70%"
  alarm_actions       = [aws_sns_topic.cloudwatch_alarms.arn]
  # ok_actions supprimé - pas de notification quand l'alarme revient à OK

  dimensions = {
    InstanceId = module.ec2.instance_id
  }

  tags = {
    Environment = "dev"
  }
}

# Outputs pour le monitoring
output "sns_topic_arn" {
  value       = aws_sns_topic.cloudwatch_alarms.arn
  description = "ARN du SNS Topic pour les alarmes"
}

output "lambda_function_name" {
  value       = aws_lambda_function.discord_notifier.function_name
  description = "Nom de la fonction Lambda"
}

output "cloudwatch_alarm_name" {
  value       = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
  description = "Nom de l'alarme CloudWatch"
}