#!/bin/bash

# Input: region and AMI ID
input="us-east-1: ami-08d6f448fd8ae9e2c"
kms_key_id="arn:aws:kms:us-east-1:123456789012:key/your-kms-key-id"

# Parse region and AMI ID
region=$(echo "$input" | cut -d':' -f1)
ami_id=$(echo "$input" | cut -d':' -f2 | xargs)

# Step 1: Copy the AMI with encryption
new_ami_id=$(aws ec2 copy-image \
  --source-image-id "$ami_id" \
  --source-region "$region" \
  --region "$region" \
  --name "Encrypted copy of $ami_id" \
  --encrypted \
  --kms-key-id "$kms_key_id" \
  --query 'ImageId' \
  --output text)

# Step 2: Wait for the new AMI to become available
echo "Waiting for AMI $new_ami_id to become available..."
aws ec2 wait image-available --image-ids "$new_ami_id" --region "$region"

# Step 3: Output updated mapping
echo "Updated mapping:"
echo "$region: $new_ami_id"