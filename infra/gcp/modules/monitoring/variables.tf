variable "name" {
  type = string
}

variable "alert_email" {
  type        = string
  description = "Where Cloud Monitoring sends alerts. Empty: policies exist but notify nobody."
  default     = ""
}

variable "labels" {
  type    = map(string)
  default = {}
}
