variable "event_rule_name"{
    type = string
}

variable "target_id" {
    type = string
}

variable "sns_topic_arn" {
    type = string
}

variable "event_rule_source" {
    type = list(string)
    default = ["aws.states"]
}


variable "event_detail_types"{
    type = list(string)
    default = ["Step Functions Execution Status Change"]
}

variable "event_statuses" {
  type    = list(string)
  default = ["FAILED", "TIMED_OUT"]
}

variable "resource_arns" {
    type = list(string)
    default = []
}