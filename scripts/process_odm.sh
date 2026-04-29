#!/bin/bash
set -euo pipefail

S3_INPUT="${S3_INPUT:-s3://rcc-processing/input}"
S3_OUTPUT="${S3_OUTPUT:-s3://rcc-processing/output}"
WORK_DIR="${WORK_DIR:-/opt/odm}"
PROJECT="project"
ODM_IMAGE="opendronemap/odm:latest"

IMAGES_DIR="$WORK_DIR/datasets/$PROJECT/images"

echo "=== Setting up working directory ==="
mkdir -p "$IMAGES_DIR"
cd "$WORK_DIR"

echo "=== Downloading images from S3 ==="
aws s3 sync "$S3_INPUT/" "$IMAGES_DIR/"
IMAGE_COUNT=$(find "$IMAGES_DIR" -maxdepth 1 -type f | wc -l)
echo "=== $IMAGE_COUNT images ready ==="

echo "=== Starting ODM $(date) ==="
docker run --rm \
  -v "$WORK_DIR/datasets:/datasets" \
  "$ODM_IMAGE" \
  --project-path /datasets \
  "$PROJECT" \
  --orthophoto-resolution 5 \
  --dsm \
  --dtm \
  --pc-quality high \
  --feature-quality high \
  --min-num-features 10000

echo "=== ODM complete $(date) ==="

echo "=== Syncing deliverables to S3 ==="
aws s3 sync \
  "$WORK_DIR/datasets/$PROJECT/odm_orthophoto/" \
  "$S3_OUTPUT/odm_orthophoto/"
aws s3 sync \
  "$WORK_DIR/datasets/$PROJECT/odm_dem/" \
  "$S3_OUTPUT/odm_dem/"
aws s3 sync \
  "$WORK_DIR/datasets/$PROJECT/odm_report/" \
  "$S3_OUTPUT/odm_report/"
aws s3 sync \
  "$WORK_DIR/datasets/$PROJECT/odm_georeferencing/" \
  "$S3_OUTPUT/odm_georeferencing/"
echo "=== Sync complete ==="
