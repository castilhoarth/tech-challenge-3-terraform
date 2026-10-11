resource "aws_sqs_queue" "main" {
  name                      = var.queue_name
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 864000
  receive_wait_time_seconds = 10
}