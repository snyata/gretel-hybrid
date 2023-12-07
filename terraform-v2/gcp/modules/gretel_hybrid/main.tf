# Formatting tolerations to match helm chart's expected input
locals {
  existing_gcp_gpu_taints = [{
    key    = "nvidia.com/gpu"
    value  = "present"
    effect = "NoSchedule"
  }]
  gpu_tolerations = [
    for toleration in concat(var.gretel_gpu_model_worker_tolerations, local.existing_gcp_gpu_taints) : {
      key      = toleration.key
      operator = "Equal"
      value    = toleration.value
      effect   = toleration.effect
    }
  ]
  cpu_tolerations = [
    for toleration in var.gretel_cpu_model_worker_tolerations : {
      key      = toleration.key
      operator = "Equal"
      value    = toleration.value
      effect   = toleration.effect
    }
  ]
}

module "gretel_workflow_worker_gcp_service_account" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v24.0.0"
  project_id = var.project_id
  name       = var.gretel_workflow_worker_gcp_service_account
}

module "gretel_model_worker_gcp_service_account" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v24.0.0"
  project_id = var.project_id
  name       = var.gretel_model_worker_gcp_service_account
}

resource "google_service_account_iam_binding" "gretel_workflow_worker_gcp_service_account" {
  service_account_id = module.gretel_workflow_worker_gcp_service_account.id
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.gretel_hybrid_namespace}/${var.gretel_workflow_worker_k8s_service_account}]",
  ]
}

resource "google_service_account_iam_binding" "gretel_model_worker_gcp_service_account" {
  service_account_id = module.gretel_model_worker_gcp_service_account.id
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.gretel_hybrid_namespace}/${var.gretel_model_worker_k8s_service_account}]",
  ]
}

module "gretel_hybrid_connector_encryption_key" {
  source  = "terraform-google-modules/kms/google"
  version = "~> 2.2.3"

  project_id         = var.project_id
  location           = var.location
  prevent_destroy    = var.gretel_credentials_encryption_key_prevent_destroy
  keyring            = var.gretel_credentials_encryption_keyring_name
  keys               = [var.gretel_credentials_encryption_key_name]
  set_encrypters_for = [var.gretel_credentials_encryption_key_name]
  set_decrypters_for = [var.gretel_credentials_encryption_key_name]
  # Encrypters is a list(string) where the string is a CSV value.
  # This is due to the kms module allowing multiple keys to be created.
  # See: https://github.com/terraform-google-modules/terraform-google-kms/blob/fc40f4ef4cf19c13206a72823f574953f36f3c85/main.tf#L83-L88
  encrypters = [join(",", var.gretel_credentials_encryption_key_users)]
  decrypters = [
    "serviceAccount:${module.gretel_workflow_worker_gcp_service_account.email}",
  ]
}

module "gretel_hybrid_source_bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v24.0.0"
  project_id    = var.project_id
  location      = var.bucket_location
  name          = var.gretel_source_bucket_name
  versioning    = true
  force_destroy = true
  iam = {
    "roles/storage.objectViewer" = [
      "serviceAccount:${module.gretel_model_worker_gcp_service_account.email}",
    ]
  }
}

module "gretel_hybrid_sink_bucket" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v24.0.0"
  project_id    = var.project_id
  location      = var.bucket_location
  name          = var.gretel_sink_bucket_name
  versioning    = true
  force_destroy = true
  iam = {
    "roles/storage.objectUser" = [
      "serviceAccount:${module.gretel_model_worker_gcp_service_account.email}",
      "serviceAccount:${module.gretel_workflow_worker_gcp_service_account.email}",
    ]
  }
}
resource "kubernetes_namespace" "gretel_hybrid_namespace" {
  metadata {
    name = var.gretel_hybrid_namespace
  }
}

resource "helm_release" "gretel_hybrid_agent" {
  name       = "gretel-agent"
  repository = var.gretel_helm_repo
  chart      = var.gretel_chart
  namespace  = var.gretel_hybrid_namespace
  depends_on = [
    kubernetes_namespace.gretel_hybrid_namespace
  ]

  values = [yamlencode({
    gretelConfig = {
      apiEndpoint      = var.gretel_api_endpoint
      apiKey           = var.gretel_api_key
      projects         = var.gretel_hybrid_projects
      artifactEndpoint = module.gretel_hybrid_sink_bucket.url
    }

    gretelWorkers = {
      images = {
        registry = var.gretel_image_registry_override_host
      }
      workflow = {
        serviceAccount = {
          name = var.gretel_workflow_worker_k8s_service_account
          annotations = {
            "iam.gke.io/gcp-service-account" = module.gretel_workflow_worker_gcp_service_account.email
          }
        }
      }

      model = {
        maxConcurrent = var.gretel_max_workers
        serviceAccount = {
          name = var.gretel_model_worker_k8s_service_account
          annotations = {
            "iam.gke.io/gcp-service-account" = module.gretel_model_worker_gcp_service_account.email
          }
        }

        resources = {
          requests = {
            cpu    = var.gretel_model_worker_pod_cpu_count
            memory = "${var.gretel_model_worker_pod_memory_gb}Gi"
          }
          limits = {
            memory = "${var.gretel_model_worker_pod_memory_gb}Gi"
          }
        }

        cpu = {
          nodeSelector = var.gretel_cpu_model_worker_node_selector
          tolerations  = var.gretel_cpu_model_worker_tolerations
        }
        gpu = {
          nodeSelector = var.gretel_gpu_model_worker_node_selector
          tolerations  = var.gretel_gpu_model_worker_tolerations
        }
      }
    }
    }),
    yamlencode(var.extra_helm_values),
  ]
}
