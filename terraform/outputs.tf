output "gcs_bucket_name" {
  description = "Name of the FAERS data lake GCS bucket"
  value       = google_storage_bucket.faers_lake.name
}

output "faers_raw_dataset" {
  description = "BigQuery dataset ID for raw FAERS data"
  value       = google_bigquery_dataset.faers_raw.dataset_id
}

output "faers_staging_dataset" {
  description = "BigQuery dataset ID for dbt staging layer"
  value       = google_bigquery_dataset.faers_staging.dataset_id
}

output "faers_mart_dataset" {
  description = "BigQuery dataset ID for dbt mart layer"
  value       = google_bigquery_dataset.faers_mart.dataset_id
}

output "pipeline_service_account_email" {
  description = "Email of the FAERS pipeline service account (use this in Kestra + dbt profiles)"
  value       = google_service_account.faers_pipeline_sa.email
}
