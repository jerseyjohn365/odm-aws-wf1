#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
exec > >(tee /var/log/odm-processing.log) 2>&1

echo "=== ODM processing instance starting $(date) ==="

# Base dependencies
apt-get update -y
apt-get install -y --no-install-recommends git curl unzip python3-pip python3-dev build-essential

# AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# Install ODM natively
git clone https://github.com/OpenDroneMap/ODM --depth 1 /odm
cd /odm
bash configure.sh install

# Pull images from S3
mkdir -p /datasets/project/images
echo "=== Pulling images from s3://${data_bucket}/${input_prefix}/ ==="
aws s3 sync s3://${data_bucket}/${input_prefix}/ /datasets/project/images/
echo "=== $(find /datasets/project/images -type f | wc -l) images ready ==="

# Run ODM — full multispectral pipeline
echo "=== Starting ODM $(date) ==="
python3 /odm/run.py \
  --project-path /datasets \
  --name project \
  --max-concurrency $(nproc) \
  --dsm \
  --dtm \
  --radiometric-calibration camera

# Push deliverables to S3
echo "=== Uploading results to s3://${data_bucket}/${output_prefix}/ ==="
aws s3 sync /datasets/project/ s3://${data_bucket}/${output_prefix}/ \
  --exclude "images/*" \
  --exclude "opensfm/undistorted/*" \
  --exclude "*.tmp"

echo "=== Done $(date) ==="
shutdown -h now
