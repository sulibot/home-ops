output "facts_file_path" {
  description = "Path to the generated network-facts.json"
  value       = local_file.ansible_network_facts.filename
}
