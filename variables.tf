variable "repo_name" {
  default = "odm-aws-wf1"
}
variable "repo_owner" {
  default = "kendrickcc"
}
variable "project" {
  default = "ODM 1600 S Hwy UU"
}
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-2"
}
variable "avail_zone" {
  default = "us-east-2a"
}
variable "data_bucket" {
  description = "S3 bucket for input images and output deliverables"
  type        = string
}
variable "input_prefix" {
  description = "S3 prefix where input images are stored"
  type        = string
  default     = "input"
}
variable "output_prefix" {
  description = "S3 prefix where processed deliverables will be written"
  type        = string
  default     = "output"
}
variable "rootBlockSize" {
  description = "Root volume size in GiB — needs headroom for images + ODM working files"
  default     = "250"
}
variable "vpc_cidr_block" {
  default = "192.168.0.0/16"
}
variable "public_subnet" {
  default = "192.168.1.0/24"
}
variable "type_selector" {
  description = "Select the instance type"
  default     = "m5a-4xlarge"
}
variable "instance_type" {
  description = "AMD instances — no Docker overhead means full RAM goes to ODM"
  type        = map(string)
  default = {
    t2-micro    = "t2.micro"     # 1 vCPU,  1 GiB,  free tier — pipeline testing only
    t3-micro    = "t3.micro"     # 2 vCPUs, 1 GiB,  free tier — pipeline testing only
    t3-small    = "t3.small"     # 2 vCPUs, 2 GiB,  ~$0.02/hr
    m5a-2xlarge = "m5a.2xlarge"  # 8 vCPUs, 32 GiB, ~$0.34/hr — small jobs
    m5a-4xlarge = "m5a.4xlarge"  # 16 vCPUs, 64 GiB, ~$0.69/hr — default
    m5a-8xlarge = "m5a.8xlarge"  # 32 vCPUs, 128 GiB, ~$1.38/hr — large surveys
  }
}
