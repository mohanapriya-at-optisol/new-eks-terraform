output "aws_s3_state_bucket_id"{
    value = aws_s3_bucket.state_s3_bucket.id
}
output "aws_s3_state_bucket_region"{
    value = aws_s3_bucket.state_s3_bucket.region
}
output "aws_s3_state_bucket_name"{
    value = aws_s3_bucket.state_s3_bucket.bucket
}
output "aws_dynamodb_table_name"{
    value = aws_dynamodb_table.terraform_locks.name
}
output "aws_dynamodb_table_arn"{
    value = aws_dynamodb_table.terraform_locks.arn
}
    