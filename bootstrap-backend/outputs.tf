output "ansible_ssm_bucket_name" {
  value = aws_s3_bucket.ansible_ssm.bucket
}