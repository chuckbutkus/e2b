# Output contract shared with modules/network/existing — envs/ compose
# against this shape regardless of which implementation is used.

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "azs" {
  value = var.azs
}
