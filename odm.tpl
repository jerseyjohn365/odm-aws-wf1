#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
exec > >(tee /var/log/odm-processing.log) 2>&1

echo "=== ODM processing instance starting $(date) ==="

# Install awscli first so the EXIT trap can upload the log
apt-get update -y
apt-get install -y --no-install-recommends awscli docker.io

# Trap fires on any exit — always sync deliverables and upload log before shutdown
trap '
  echo "=== Syncing deliverables to S3 ==="
  aws s3 sync /datasets/project/ s3://${data_bucket}/${output_prefix}/ \
    --exclude "images/*" \
    --exclude "opensfm/undistorted/*" \
    --exclude "*.tmp" 2>/dev/null || true
  aws s3 cp /var/log/odm-processing.log s3://${data_bucket}/logs/odm-processing.log 2>/dev/null || true
  shutdown -h now
' EXIT

# Poll for spot interruption notice every 5 seconds in background
(
  while true; do
    if curl -s -f http://169.254.169.254/latest/meta-data/spot/termination-time 2>/dev/null; then
      echo "=== SPOT INSTANCE RECLAIMED BY AWS — not an error, rerun the job ==="
      exit 0
    fi
    sleep 5
  done
) &
SPOT_MONITOR_PID=$!

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
  --max-concurrency $(nproc) \
  --dsm \
  --dtm \
  --radiometric-calibration camera+sun \
  --skip-report \
  project

echo "=== Done $(date) ==="
