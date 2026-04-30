#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
exec > >(tee /var/log/odm-processing.log) 2>&1

echo "=== ODM processing instance starting $(date) ==="

# Install awscli first so the EXIT trap can upload the log
apt-get update -y
apt-get install -y --no-install-recommends awscli docker.io python3-gdal

# Trap fires on any exit — always sync deliverables and upload log before shutdown
trap '
  echo "=== Syncing deliverables to S3 ==="
  aws s3 sync /datasets/project_rgb/ s3://${data_bucket}/${output_prefix}/rgb/ \
    --exclude "images/*" \
    --exclude "opensfm/undistorted/*" \
    --exclude "*.tmp" 2>/dev/null || true
  aws s3 sync /datasets/project_ms/ s3://${data_bucket}/${output_prefix}/ms/ \
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

# Pull and run ODM — two passes, RGB and multispectral
mkdir -p /datasets/project_rgb/images /datasets/project_ms/images

# Pull input images from S3
echo "=== Pulling images from s3://${data_bucket}/${input_prefix}/ ==="
aws s3 sync s3://${data_bucket}/${input_prefix}/ /datasets/images_raw/
echo "=== $(find /datasets/images_raw -type f | wc -l) images downloaded ==="
echo "=== Extensions present: $(find /datasets/images_raw -type f | sed 's/.*\.//' | sort -u | tr '\n' ' ') ==="
echo "=== Sample filenames: ===" && ls /datasets/images_raw | head -5 || true

# Split by filename pattern — DJI M3M: _W.JPG = RGB wide, _MS_*.TIF = multispectral bands
find /datasets/images_raw -iname "*_D.JPG" -exec cp {} /datasets/project_rgb/images/ \;
find /datasets/images_raw -iname "*_MS_*.TIF" -exec cp {} /datasets/project_ms/images/ \;
echo "=== RGB: $(find /datasets/project_rgb/images -type f | wc -l) JPGs ==="
echo "=== MS:  $(find /datasets/project_ms/images  -type f | wc -l) TIFs ==="

# Pass 1 — RGB orthophoto + PNG (only if wide-camera JPGs were found)
RGB_COUNT=$(find /datasets/project_rgb/images -type f | wc -l)
echo "=== project_rgb/images contents: ==="
ls /datasets/project_rgb/images | head -20 || true
if [ "$RGB_COUNT" -gt 4 ]; then
  echo "=== Starting ODM RGB pass ($RGB_COUNT images) $(date) ==="
  docker run --rm \
    -v /datasets:/datasets \
    opendronemap/odm:latest \
    --project-path /datasets \
    --max-concurrency $(nproc) \
    --dsm \
    --dtm \
    --orthophoto-png \
    --skip-report \
    project_rgb || echo "=== WARNING: RGB pass failed, continuing to MS pass ==="
  echo "=== RGB pass done $(date) ==="
else
  echo "=== Skipping RGB ODM pass ($RGB_COUNT images found, need >4) ==="
fi

# Pass 2 — multispectral orthophoto
echo "=== Starting ODM multispectral pass $(date) ==="
docker run --rm \
  -v /datasets:/datasets \
  opendronemap/odm:latest \
  --project-path /datasets \
  --max-concurrency $(nproc) \
  --dsm \
  --dtm \
  --primary-band NIR \
  --radiometric-calibration camera+sun \
  --skip-report \
  project_ms
echo "=== Multispectral pass done $(date) ==="

# Generate RGB composite PNG from MS orthophoto for portfolio
# Uses Red, Green, Blue bands identified by description; falls back to bands 1,2,3
if [ -f "$ORTHO" ]; then
  echo "=== Generating RGB composite PNG ==="
  RED_B=$(gdalinfo "$ORTHO" | awk '/^Band [0-9]/{band=$2} /Description = Red$/{print band; exit}')
  GRN_B=$(gdalinfo "$ORTHO" | awk '/^Band [0-9]/{band=$2} /Description = Green$/{print band; exit}')
  BLU_B=$(gdalinfo "$ORTHO" | awk '/^Band [0-9]/{band=$2} /Description = Blue$/{print band; exit}')
  RED_B="$${RED_B:-1}"
  GRN_B="$${GRN_B:-2}"
  BLU_B="$${BLU_B:-3}"
  echo "=== RGB composite using R=band$${RED_B} G=band$${GRN_B} B=band$${BLU_B} ==="
  gdal_translate \
    -b "$${RED_B}" -b "$${GRN_B}" -b "$${BLU_B}" \
    -of PNG -scale \
    "$ORTHO" \
    /datasets/project_ms/odm_orthophoto/rgb_composite.png
  echo "=== RGB composite PNG complete ==="
fi

# Compute NDVI from multispectral orthophoto
# ODM band order with --primary-band NIR: 1=Red 2=Green 3=NIR 4=RedEdge (Blue dropped as redundant)
ORTHO=/datasets/project_ms/odm_orthophoto/odm_orthophoto.tif
if [ -f "$ORTHO" ]; then
  BAND_COUNT=$(gdalinfo "$ORTHO" | grep -c "^Band [0-9]")
  echo "=== Multispectral orthophoto has $BAND_COUNT band(s) ==="
  if [ "$BAND_COUNT" -ge 3 ]; then
    echo "=== Computing NDVI ==="
    # Identify NIR and Red band numbers from gdalinfo (band number and description are on separate lines)
    NIR_BAND=$(gdalinfo "$ORTHO" | awk '/^Band [0-9]/{band=$2} /Description = NIR/{print band; exit}')
    RED_BAND=$(gdalinfo "$ORTHO" | awk '/^Band [0-9]/{band=$2} /Description = Red$/{print band; exit}')
    NIR_BAND="$${NIR_BAND:-3}"
    RED_BAND="$${RED_BAND:-1}"
    echo "=== Using NIR=band$${NIR_BAND} Red=band$${RED_BAND} ==="
    gdal_calc.py \
      -A "$ORTHO" --A_band="$${NIR_BAND}" \
      -B "$ORTHO" --B_band="$${RED_BAND}" \
      --outfile=/datasets/project_ms/odm_orthophoto/ndvi.tif \
      --calc="(A.astype(float)-B.astype(float))/(A.astype(float)+B.astype(float))" \
      --NoDataValue=-9999 \
      --type=Float32 \
      --overwrite
    echo "=== NDVI complete ==="
  else
    echo "=== WARNING: only $BAND_COUNT band(s) found — skipping NDVI ==="
  fi
else
  echo "=== WARNING: multispectral orthophoto not found at $ORTHO ==="
fi
