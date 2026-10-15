output "get_credentials" {
  value = module.gke.get_credentials
}

output "ssh_ops_vm" {
  value = module.bastion.ssh_command
}

output "redis_host" {
  value = module.redis.host
}

output "image_prefix" {
  value = module.registry.image_prefix
}
