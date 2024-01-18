# Déploiement Kubernetes

## Vue d'ensemble

Ce projet est conçu pour déployer une infrastructure robuste et sécurisée sur Kubernetes, incluant un serveur ***Nginx***, une base de données ***PostgreSQL***, un nœud ***Ethereum (Geth)*** et une ***Cloud Function*** déclenchée par Google Cloud Scheduler pour effectuer des requêtes CURL périodiques.

## Composants

- **Nginx** : Un serveur web léger et performant, configuré pour servir une application ou des fichiers statiques.
- **PostgreSQL** : Un système de gestion de base de données relationnelle, configuré pour stocker des données de manière sécurisée et performante.
- **Ethereum (Geth)** : Un client Ethereum (Go Ethereum) déployé pour interagir avec le réseau Ethereum.
- **Cloud Function** : Une fonction déclenchée par un Scheduler pour effectuer un curl sur l'index Nginx à des intervalles réguliers. Ceci est sécurisé à l'aide d'un service account dédié.

## Pré-requis

- Un compte Google Cloud avec les services suivants activés :
- Google Kubernetes Engine (GKE)
- Google Cloud SQL
- Google Cloud Functions
- Google Cloud Scheduler
- Google Cloud Pub/Sub
- Terraform installé localement.
- kubectl installé localement.
- Accès configuré à votre compte Google Cloud via le SDK Google Cloud.

## Installation et déploiement

1. **Cloner le projet** :

```bash
git clone https://github.com/MatthieuLvsr/tp-infra.git
```

1. **Configurer Terraform** :

Initialisez votre configuration Terraform.

```bash
cd gke-cluster
terraform init
cd ../nginx-kubernetes
terraform apply
```

1. **Définir les variables d'environnement** :

Configurez les variables nécessaires pour le déploiement. Ces dernières se situent dans les fichiers terraform.tfvars

```tf
project_id = [VOTRE_PROJET_ID]
region     = [VOTRE_REGION]
```

1. **Appliquer la configuration Terraform** :

Appliquez la configuration pour déployer l'infrastructure.

```bash
terraform apply
Confirmez en saisissant yes lorsque vous êtes invité.
```

1. **Vérifier le déploiement** :

Vérifiez que toutes les ressources ont été créées avec succès en utilisant la console Google Cloud ou les commandes CLI appropriées (gcloud, kubectl).

## Sécurité

Assurez-vous de configurer *--http.corsdomain* avec des valeurs spécifiques pour limiter les domaines pouvant accéder à votre nœud Ethereum.
Ne divulguez pas de secrets ou de mots de passe dans vos fichiers de configuration. Utilisez des mécanismes de gestion des secrets appropriés.
Configurez des règles de pare-feu et des restrictions d'accès réseau pour vos services, selon les besoins.