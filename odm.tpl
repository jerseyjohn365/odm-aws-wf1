#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
exec > >(tee /var/log/odm-processing.log) 2>&1

# Always upload log and shut down on exit, success or failure
trap 'aws s3 cp /var/log/odm-processing.log s3://${data_bucket}/logs/odm-processing.log 2>/dev/null || true; shutdown -h now' EXIT

echo "=== ODM processing instance starting $(date) ==="

# Install Docker and AWS CLI v2
apt-get install -y --no-install-recommends docker.io awscli

# Pull and run ODM — single container, no web UI
mkdir -p /datasets/project/images

# Pull input images from S3
echo "=== Pulling images from s3://${data_bucket}/${input_prefix}/ ==="
aws s3 sync s3://${data_bucket}/${input_prefix}/ /datasets/project/images/
echo "=== $(find /datasets/project/images -type f | wc -l) images ready ==="

# Run ODM
echo "=== Starting ODM $(date) ==="
docker run --rm \
  -v /datasets:/datasets \
  opendronemap/odm \
  --project-path /datasets \
  --name project \
  --max-concurrency $(nproc) \
  --dsm \
  --dtm \
  --radiometric-calibration camera+sun

# Push deliverables to S3
echo "=== Uploading results to s3://${data_bucket}/${output_prefix}/ ==="
aws s3 sync /datasets/project/ s3://${data_bucket}/${output_prefix}/ \
  --exclude "images/*" \
  --exclude "opensfm/undistorted/*" \
  --exclude "*.tmp"

echo "=== Done $(date) ==="
shutdown -h now
