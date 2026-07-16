output "node_service_account_email" {
  value = google_service_account.node.email
}

output "node_pool_id" {
  value = google_container_node_pool.this.id
}
