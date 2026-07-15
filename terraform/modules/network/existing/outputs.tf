output "vpc_id" {
  value = data.aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [for s in data.aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  value = [for s in data.aws_subnet.private : s.id]
}

output "azs" {
  value = distinct([for s in data.aws_subnet.private : s.availability_zone])
}
