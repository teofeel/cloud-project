variable "bucket_name" {
  type        = string
  description = "unique name"
}

variable "environment" {
  type        = string
  description = "dev / prod"
  default     = "dev"
}

variable "tags" {
  type        = map(string)
  description = "for easier organization"
  default     = {}
}