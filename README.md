# ODM AWS Workflow — DJI M3M Multispectral Pipeline

Provision an EC2 instance on AWS using Terraform to run headless [OpenDroneMap](https://www.opendronemap.org/) on DJI Mavic 3 Multispectral imagery. Everything runs from GitHub Actions — no local Terraform installation required. Input images are pulled from S3, processed through a two-pass ODM pipeline, and all deliverables are synced back to S3 before the instance shuts down.

Forked from [kendrickcc/odm-aws-wf1](https://github.com/kendrickcc/odm-aws-wf1) — Chris Kendrick's original WebODM/ClusterODM setup on AWS. This fork replaces the WebODM stack with a fully headless ODM pipeline purpose-built for DJI M3M multispectral surveys.

---

## What it does

1. Provisions a fresh EC2 instance (on-demand) via Terraform
2. Downloads raw imagery from S3
3. Splits images by filename pattern into RGB and multispectral sets
4. **Pass 1 — RGB:** Runs ODM on `*_D.JPG` wide-camera images to produce an RGB orthophoto
5. **Pass 2 — Multispectral:** Runs ODM on `*_MS_*.TIF` images with radiometric calibration (`camera+sun`) to produce a calibrated multispectral orthophoto (Green, Red, NIR, RedEdge bands)
6. Computes NDVI from the multispectral orthophoto (NIR and Red bands)
7. Syncs all outputs to S3 and shuts down

The instance self-terminates when processing is complete. An EXIT trap ensures outputs and logs are always synced to S3 even if the script fails mid-run.

---

## Supported imagery

DJI Mavic 3 Multispectral (M3M). Files are split by filename pattern:

| Pattern | Pass |
|---|---|
| `*_D.JPG` | RGB orthophoto |
| `*_MS_G.TIF`, `*_MS_R.TIF`, `*_MS_RE.TIF`, `*_MS_NIR.TIF` | Multispectral orthophoto + NDVI |

PPK files (`.nav`, `.obs`, `.bin`, `.MRK`) are downloaded alongside images and ignored by ODM.

---

## S3 layout

```
s3://<data_bucket>/
  input/          ← upload raw imagery here before running
  output/
    rgb/          ← RGB orthophoto, DSM, DTM
    ms/           ← multispectral orthophoto (5-band), NDVI GeoTIFF
  logs/
    odm-processing.log
```

---

## Setup

### 1. S3 buckets

You need two S3 buckets:

- **State bucket** — stores the Terraform state file. Create this manually and record the name.
- **Data bucket** — stores input imagery and receives processed outputs. Can be the same bucket.

### 2. IAM role for OIDC

This workflow uses [OpenID Connect](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) to authenticate GitHub Actions with AWS — no long-lived access keys required.

Create an IAM role that trusts GitHub's OIDC provider and attach a policy granting:
- EC2 full access (for provisioning instances, VPC, IAM instance profiles)
- S3 read/write on both buckets

Record the role ARN.

### 3. GitHub Secrets

In your repository under **Settings → Secrets and variables → Actions**, create:

| Secret | Value |
|---|---|
| `AWS_ROLE_ARN` | ARN of the IAM role created above |
| `BUCKET` | Name of the S3 state bucket |
| `DATA_BUCKET` | Name of the S3 data bucket |

### 4. Upload imagery

Upload your DJI M3M imagery to `s3://<data_bucket>/input/` before running the Apply workflow.

### 5. Review variables

Check `variables.tf` and adjust if needed:

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-2` | AWS region |
| `avail_zone` | `us-east-2a` | Availability zone |
| `type_selector` | `m5a-4xlarge` | Instance type key |
| `rootBlockSize` | `250` | Root volume size in GiB |
| `input_prefix` | `input` | S3 prefix for input imagery |
| `output_prefix` | `output` | S3 prefix for processed outputs |

For large surveys (>1000 images), `m5a.4xlarge` (16 vCPU / 64 GiB) is a reasonable default. For very large jobs, bump to `m5a-8xlarge`.

---

## Running a job

All workflows are manually triggered under **Actions → [workflow name] → Run workflow**.

| Workflow | Action |
|---|---|
| **A — Terraform Plan** | Validates config, shows what will be created. Run this first. |
| **B — Terraform Apply** | Provisions infrastructure and starts ODM processing. |
| **C — Terraform Output** | Shows instance ID and public IP from the current state. |
| **X — Terraform Destroy** | Tears down all provisioned resources. Run when done. |
| **Z — Terraform State Remove** | Deletes the state file from S3. Use if state gets out of sync. |

### Typical workflow

1. Upload imagery to S3
2. Run **A — Plan** to validate
3. Run **B — Apply** to start processing
4. Wait — the instance will run ODM and self-terminate when done (typically 1–3 hours depending on image count and instance size)
5. Download outputs from `s3://<data_bucket>/output/`
6. Run **X — Destroy** to clean up AWS resources

> **Note:** Terraform Apply completes in a few minutes, but ODM processing continues on the instance after that. The instance terminates itself when done — watch for it to disappear in the EC2 console, then retrieve your outputs from S3.

---

## Outputs

After processing, retrieve from S3:

| File | Description |
|---|---|
| `output/rgb/odm_orthophoto/odm_orthophoto.tif` | RGB orthophoto GeoTIFF |
| `output/rgb/odm_orthophoto/odm_orthophoto.png` | RGB orthophoto PNG |
| `output/rgb/odm_dem/dsm.tif` | Digital Surface Model |
| `output/rgb/odm_dem/dtm.tif` | Digital Terrain Model |
| `output/ms/odm_orthophoto/odm_orthophoto.tif` | Multispectral orthophoto (5 bands: Red, Green, NIR, RedEdge + alpha) |
| `output/ms/odm_orthophoto/ndvi.tif` | NDVI GeoTIFF (Float32, range −1 to 1) |
| `logs/odm-processing.log` | Full processing log |

The multispectral orthophoto is radiometrically calibrated reflectance data. Open it in QGIS and use the Raster Calculator for additional indices (e.g. NDRE using bands 3 and 4).

---

## Acknowledgements

Forked from [kendrickcc/odm-aws-wf1](https://github.com/kendrickcc/odm-aws-wf1). Chris Kendrick's original project laid the groundwork for GitHub Actions-driven Terraform/ODM on AWS. This fork adapts it for automated headless multispectral processing without a WebODM interface.
