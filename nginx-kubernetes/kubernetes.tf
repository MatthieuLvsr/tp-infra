terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.52.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.1"
    }
  }
}

data "terraform_remote_state" "gke" {
  backend = "local"

  config = {
    path = "../gke-cluster/terraform.tfstate"
  }
}

# Retrieve GKE cluster information
provider "google" {
  project = data.terraform_remote_state.gke.outputs.project_id
  region  = data.terraform_remote_state.gke.outputs.region
}

# Configure kubernetes provider with Oauth2 access token.
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/client_config
# This fetches a new token, which will expire in 1 hour.
data "google_client_config" "default" {}

data "google_container_cluster" "my_cluster" {
  name     = data.terraform_remote_state.gke.outputs.kubernetes_cluster_name
  location = data.terraform_remote_state.gke.outputs.region
}

provider "kubernetes" {
  host = data.terraform_remote_state.gke.outputs.kubernetes_cluster_host

  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.my_cluster.master_auth[0].cluster_ca_certificate)
}

# --------------------------------------------
# NGINX
# --------------------------------------------

resource "kubernetes_deployment" "nginx" {
  metadata {
    name = "scalable-nginx-example"
    labels = {
      App = "ScalableNginxExample"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        App = "ScalableNginxExample"
      }
    }
    template {
      metadata {
        labels = {
          App = "ScalableNginxExample"
        }
      }
      spec {
        container {
          image = "nginx:1.7.8"
          name  = "example"

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "nginx" {
  metadata {
    name = "nginx-example"
  }
  spec {
    selector = {
      App = kubernetes_deployment.nginx.spec.0.template.0.metadata[0].labels.App
    }
    port {
      port        = 80
      target_port = 80
    }

    type = "LoadBalancer"
  }
}
output "lb_ip" {
  value = kubernetes_service.nginx.status.0.load_balancer.0.ingress.0.ip
}

# --------------------------------------------
# GRAFANA
# --------------------------------------------

resource "kubernetes_deployment" "grafana" {
  metadata {
    name = "grafana"
    labels = {
      App = "Grafana"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        App = "Grafana"
      }
    }
    template {
      metadata {
        labels = {
          App = "Grafana"
        }
      }
      spec {
        container {
          image = "grafana/grafana:latest"
          name  = "grafana"

          port {
            container_port = 3000
          }

          resources {
            limits = {
              cpu    = "200m"
              memory = "200Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "100Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "grafana" {
  metadata {
    name = "grafana"
  }
  spec {
    selector = {
      App = kubernetes_deployment.grafana.metadata[0].labels.App
    }
    port {
      port        = 3000
      target_port = 3000
    }

    type = "LoadBalancer"
  }
}

output "grafana_lb_ip" {
  value = kubernetes_service.grafana.status.0.load_balancer.0.ingress.0.ip
}

# --------------------------------------------
# Cloud Function
# --------------------------------------------

# Creation of the serice account
resource "google_service_account" "cloud_function_account" {
  account_id   = "cloud-function-account"
  display_name = "Cloud Function Service Account"
}

# Setup service account role
resource "google_project_iam_member" "invoker_role" {
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.cloud_function_account.email}"
}


# Bucket to store the cloud function code
resource "google_storage_bucket" "function_bucket" {
  name = "my-cloud-function-bucket-restricted"
}

# Upload the cloud function source code to the bucket
resource "google_storage_bucket_object" "function_code" {
  name   = "curl-nginx-index.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = "./curl-nginx-index.zip"
}

# Pub/Sub topic used to trigger the cloud function
resource "google_pubsub_topic" "nginx_curl_topic" {
  name = "nginx-curl-topic"
}

# Cloud Function that is triggered by Pub/Sub
resource "google_cloudfunctions_function" "nginx_curl" {
  service_account_email = google_service_account.cloud_function_account.email
  name                  = "curl-nginx-function"
  description           = "A function that curls Nginx index page"
  runtime               = "nodejs12"
  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.function_bucket.name
  source_archive_object = google_storage_bucket_object.function_code.name
  entry_point           = "curlNginxIndex"
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.nginx_curl_topic.name
  }
}

# Cloud Scheduler job to trigger the Cloud Function
resource "google_cloud_scheduler_job" "nginx_curl_scheduler" {
  name     = "curl-nginx-index-everyday"
  schedule = "0 7 * * *"
  time_zone = "Europe/Bucharest"

  pubsub_target {
    topic_name = google_pubsub_topic.nginx_curl_topic.id
    data       = base64encode("Curl Nginx")
  }
}

# Output the Cloud Function's trigger URL
output "nginx_curl_function_url" {
  value = google_cloudfunctions_function.nginx_curl.https_trigger_url
}

# IAM policies to allow Cloud Scheduler to trigger the Cloud Function
resource "google_cloudfunctions_function_iam_policy" "nginx_curl_iam" {
  project     = var.project_id  # Assurez-vous d'avoir une variable ou une valeur pour le projet
  region      = var.region   # Assurez-vous d'avoir une variable ou une valeur pour la région
  cloud_function = google_cloudfunctions_function.nginx_curl.name

  policy_data = data.google_iam_policy.admin.policy_data
}

data "google_iam_policy" "admin" {
  binding {
    role = "roles/cloudfunctions.invoker"

    members = [
      "serviceAccount:${google_service_account.cloud_function_account.email}",
    ]
  }
}

# --------------------------------------------
# Ethereum node
# --------------------------------------------

resource "kubernetes_deployment" "geth" {
  metadata {
    name = "geth-node"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "geth-node"
      }
    }

    template {
      metadata {
        labels = {
          app = "geth-node"
        }
      }

      spec {
        container {
          image = "ethereum/client-go:latest"  # Utilisez l'image officielle de Geth
          name  = "geth-node"
          args  = [
            "--http",
            "--http.addr=0.0.0.0",
            "--http.port=8545",
            "--http.corsdomain=http://mattlvsr.fr",
            "--http.vhosts=*",
            "--ipcdisable",
            "--syncmode=snap",  # Utilisez "full" pour un nœud complet, "fast" pour un nœud rapide
            # Ajoutez d'autres options de configuration Geth ici
          ]

          port {
            container_port = 8545  # Port pour l'interface HTTP RPC
          }
        }
      }
    }
  }
}
# --------------------------------------------
# Postgres
# --------------------------------------------

resource "google_sql_database_instance" "postgres_instance" {
  name             = "postgres-instance"
  database_version = "POSTGRES_13"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    backup_configuration {
      enabled = true
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }
}

resource "google_sql_database" "postgres_db" {
  name     = "mydatabase"
  instance = google_sql_database_instance.postgres_instance.name
}

resource "google_sql_user" "postgres_user" {
  name     = "dbuser"
  instance = google_sql_database_instance.postgres_instance.name
  password = "dbpassword"
}

output "postgres_instance_address" {
  value = google_sql_database_instance.postgres_instance.first_ip_address
}
