variable "queue_name" {
  type = string
}

variable "fifo_queue" {
  type= bool
  default = false
}

variable "delay_seconds" {
  type    = number
  default = 10
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
}

variable "max_message_size" {
  type    = number
  default = 2048
}

variable "message_retention_seconds" {
  type    = number
  default = 86400
}

variable "receive_wait_time_seconds" {
  type    = number
  default = 2
}

variable "sqs_managed_sse_enabled" {
  type    = bool
  default = true
}