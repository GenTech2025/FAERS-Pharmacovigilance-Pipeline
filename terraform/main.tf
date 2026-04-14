terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.6"
    }
  }
}

provider "google" {
  credentials = file(var.credentials)
  project     = var.project
  region      = var.region
}

# ── Service Account ──────────────────────────────────────────────────────────

resource "google_service_account" "faers_pipeline_sa" {
  account_id   = "faers-pipeline-sa"
  display_name = "FAERS Pipeline Service Account"
  description  = "Used by Kestra and dbt to access GCS and BigQuery"
}

resource "google_project_iam_member" "sa_storage_admin" {
  project = var.project
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.faers_pipeline_sa.email}"
}

resource "google_project_iam_member" "sa_bq_data_editor" {
  project = var.project
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.faers_pipeline_sa.email}"
}

resource "google_project_iam_member" "sa_bq_job_user" {
  project = var.project
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.faers_pipeline_sa.email}"
}

resource "google_service_account_key" "faers_pipeline_sa_key" {
  service_account_id = google_service_account.faers_pipeline_sa.name
}

resource "local_file" "sa_key_file" {
  content  = base64decode(google_service_account_key.faers_pipeline_sa_key.private_key)
  filename = "${path.module}/keys/faers-pipeline-sa.json"
}

# ── GCS Data Lake Bucket ──────────────────────────────────────────────────────

resource "google_storage_bucket" "faers_lake" {
  name          = var.gcs_bucket_name
  location      = var.location
  storage_class = "STANDARD"
  force_destroy = true

  # Prevent accidental public exposure
  public_access_prevention = "enforced"

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}

# ── BigQuery Datasets ─────────────────────────────────────────────────────────

resource "google_bigquery_dataset" "faers_raw" {
  dataset_id    = "faers_raw"
  friendly_name = "FAERS Raw"
  description   = "Raw FAERS flat files loaded directly from GCS — no transformations"
  location      = var.location
}

resource "google_bigquery_dataset" "faers_staging" {
  dataset_id    = "faers_staging"
  friendly_name = "FAERS Staging"
  description   = "dbt staging layer — cleaned, cast, and deduplicated views over faers_raw"
  location      = var.location
}

resource "google_bigquery_dataset" "faers_mart" {
  dataset_id    = "faers_mart"
  friendly_name = "FAERS Mart"
  description   = "dbt mart layer — analytical tables powering the Looker Studio dashboard"
  location      = var.location
}
