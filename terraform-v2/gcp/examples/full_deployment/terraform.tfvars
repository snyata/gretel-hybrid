# Provide an existing GCP Project ID
project_id      = "synapse-v0-1-1"

# The deployment name is used to name created resources.
# eg. the GKE cluster will be: gretel-hybrid-cluster
deployment_name = "gretel-hybrid"

# Set the below variables as desired.
location        = "us-central1"
node_locations  = ["us-central1-a", "us-central1-b", "us-central1-c"]
bucket_location = "US"
gke_version     = "1.27.9-gke.1092000"

# GCS bucket names need to be globally unique. Change these. These buckets will be created for you.
gretel_source_bucket_name = "gretel-hybrid-source"
gretel_sink_bucket_name   = "gretel-hybrid-sink"

# Provide a list of IAM principal identifiers (users, service accounts, etc.) that are allowed to perform an encrypt operation using the KMS key used for credentials encryption. See: https://cloud.google.com/iam/docs/principal-identifiers
# example: ["user:ben@gretel.ai"]
gretel_credentials_encryption_key_users = ["user:core@synavate.tech"]

# Uncomment these two lines for a test/sandbox deployment you plan to destroy afterward
cluster_prevent_destroy = false
gretel_credentials_encryption_key_prevent_destroy = false
