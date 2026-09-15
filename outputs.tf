output "vpc_id" {
  value = aws_vpc.main.id
}
output "public_ip" {
  value = aws_instance.web.public_ip
}
output "bucket_name" {
  value = aws_s3_bucket.assets.bucket
}