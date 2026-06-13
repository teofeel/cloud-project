variable sns_topic_name{
    type = string
}

variable sns_protocol {
    type = string
    default = "lambda"
}

variable sns_endpoint {
    type = string
}

variable "raw_message_delivery" {
  type = bool
  default = false
}