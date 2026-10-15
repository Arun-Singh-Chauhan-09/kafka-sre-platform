variable "name" {
  type = string
}

variable "zone" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "e2-small"
}

variable "labels" {
  type    = map(string)
  default = {}
}
