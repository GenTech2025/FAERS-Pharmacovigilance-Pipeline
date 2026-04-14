variable "project" {
  description = "GCP Project ID"
  # Set via TF_VAR_project env var or override in terraform.tfvars
}

variable "region" {
  description = "GCP region for compute resources"
  default     = "us-central1"
}

variable "location" {
  description = "GCS bucket and BigQuery dataset location (multi-region)"
  default     = "US"
}

variable "gcs_bucket_name" {
  description = "Globally unique GCS bucket name for the FAERS data lake"
  # Recommended pattern: de-zoomcamp-faers-lake-<your-project-id>
  # GCS bucket names must be globally unique across all GCP accounts
}
