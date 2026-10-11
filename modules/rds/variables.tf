variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "eks_security_group" {
  type = string
}

variable "eks_security_group_id" {
  type    = string
  default = ""
}

variable "instances" {
  type = map(object({
    username  = string
    databases = list(string)
  }))
}