terraform {
  required_version = ">= 1.1.0"
}

variable "name" {
    type = string
    default = "World"
}

resource "null_resource" "null_resource_simple" {
    triggers = {
      the_greeting = "Hello ${var.name}"
    }
    provisioner "local-exec" {
        command = "echo Hello '${var.name}'"
    }
}

output "greeting" {
  value = null_resource.null_resource_simple.triggers.the_greeting
}