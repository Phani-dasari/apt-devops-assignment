output "alb_dns_name" {
  description = "Public ALB URL"
  value       = aws_lb.app.dns_name
}
