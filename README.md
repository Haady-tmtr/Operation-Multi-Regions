# Operation-Multi-Regions
Infrastructure AWS multi-régions avec Terraform et backend distant


> Infrastructure AWS multi-région provisionnée en IaC (Terraform), configurée sans SSH via AWS Systems Manager (Ansible + SSM).


Projet réalisé pour démontrer une maîtrise concrète des outils d'infrastructure cloud : provisioning d'une architecture réseau complète (VPC, subnets, EC2, S3, IAM) avec Terraform, refactoring en modules réutilisables pour un déploiement multi-environnement et multi-région, et configuration des serveurs via Ansible en utilisant AWS Systems Manager - sans port SSH ouvert, sans IP publique de gestion, sans clé à distribuer.

## Architecture

```


                          ┌───────────────────────────────────────────┐
                          │              Backend S3 partagé           │
                          │   (state Terraform + bucket transfert SSM)│
                          └───────────────────────┬───────────────────┘
                                                  │
              ┌───────────────────────────────────┼───────────────────────────────────┐
              ▼                                   ▼                                   ▼
   ┌─────────────────────┐          ┌──────────────────────────┐            ┌─────────────────────┐
   │ environments/staging│          │ environments/            │            │ environments/prod   │
   │      (eu-west-3)    │          │ staging-eu-west-1        │            │     (eu-west-3)     │
   │                     │          │      (eu-west-1)         │            │                     │
   │  module "platform"  │          │  module "platform"       │            │  module "platform"  │
   └──────────┬──────────┘          └──────────┬───────────────┘            └─────────┬───────────┘
              │                                │                                      │
              ▼                                ▼                                      ▼
   ┌────────────────────────────────────────────────────────────────────────────────────────┐
   │            	Infrastructure	AWS						    │
   │	       VPC · subnets public/private · IGW · route table · security groups           │
   │                   EC2 (Agent SSM + Nginx) · S3 bucket assets · rôle IAM                │
   └────────────────────────────────────────┬───────────────────────────────────────────────┘
                                            │  (agent SSM, pas de SSH, ni d'IP publique requise)
                                            ▼
                          ┌──────────────────────────────────────────┐
                          │        Poste local / CI                  │
                          │  ansible-inventory (dynamique, par tags) │
                          │  ansible-playbook -> configure-web.yml   │
                          │  connexion via community.aws.aws_ssm     │
                          └──────────────────────────────────────────┘




``` 


---

## Stack technique

| Outil | Rôle |
|---|---|
| Terraform | Provisioning IaC : VPC, subnets, EC2, S3, IAM, backend S3 |
| Module Terraform réutilisable (`modules/platform`) | Ressources partagées entre staging/prod/régions |
| AWS S3 (backend) | Stockage distant du state Terraform, versionné |
| AWS EC2 | Instances Amazon Linux 2023 exécutant Nginx |
| AWS Systems Manager (SSM) | Connexion aux instances sans SSH, sans IP publique de gestion |
| Ansible | Configuration des serveurs (installation Nginx, déploiement de contenu) |
| Ansible dynamic inventory (`amazon.aws.aws_ec2`) | Découverte automatique des instances par tags, multi-région |
| AWS S3 (bucket dédié) | Transfert des fichiers de modules Ansible via le connecteur SSM |

---



---

## Prérequis

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.16.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installé et configuré
- Un compte AWS avec les droits nécessaires (EC2, S3, IAM, VPC).
- Python 3 + [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- [AWS Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) - **indispensable**, c'est lui qui établit le tunnel chiffré entre le poste local et l'agent SSM sur l'EC2 :

  ```bash
  # Ubuntu/Debian
  curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
  sudo dpkg -i session-manager-plugin.deb
  ```
- Dépendances Python/Ansible :
  ```bash
  pip install boto3 botocore "botocore[crt]"
  ansible-galaxy collection install amazon.aws community.aws
  ```

---




## Installation

### 1. Cloner le repo

```bash
git clone https://github.com/Haady-tmtr/Operation-Multi-Regions.git
cd Operation-Multi-Regions
```

### 2. Créer le backend Terraform (une seule fois)

```bash
cd bootstrap-backend
terraform init
terraform plan   # attendu : ressources à créer (bucket S3 + config)
terraform apply
terraform output ansible_ssm_bucket_name   # noter la valeur, réutilisée dans ansible/aws_ec2.yml
cd ..
```

### 3. Déployer chaque environnement

```bash
cd environments/staging
terraform init -backend-config=backend.hcl
terraform plan -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars
```

```bash 
cd ../staging-eu-west-1
terraform init -backend-config=backend.hcl
terraform apply -var-file=staging.tfvars

```

```bash
cd ../prod
terraform init -backend-config=backend.hcl
terraform apply -var-file=prod.tfvars
cd ../..
```


Attendre 1 à 2 minutes après chaque `apply` pour laisser le temps à l'agent SSM de s'enregistrer auprès d'AWS.

### 4. Vérifier que les instances sont visibles par SSM

```bash
aws ssm describe-instance-information --region eu-west-3
aws ssm describe-instance-information --region eu-west-1
```
-> Chercher `"PingStatus": "Online"` pour chaque instance.

### 5. Configurer `ansible/aws_ec2.yml`

Renseigner le nom du bucket S3 récupéré à l'étape 2 dans `ansible_aws_ssm_bucket_name`.

### 6. Vérifier l'inventaire dynamique (depuis la racine du projet)

```bash
ansible-inventory -i ansible/aws_ec2.yml --graph
```
-> Doit afficher les groupes `role_web`, `env_staging`, `env_prod`, `region_eu_west_3`, `region_eu_west_1`.

### 7. Configurer les serveurs

```bash
ansible-playbook -i ansible/aws_ec2.yml ansible/configure-web.yml
```
-> Installe et démarre Nginx sur toutes les instances taguées `Role: web`, via un tunnel SSM chiffré (aucun port entrant, aucune IP publique de gestion).




---

## Structure du projet



```

Operation-Multi-Regions/
├── ansible/
│   ├── aws_ec2.yml            # Inventaire dynamique multi-région (plugin amazon.aws.aws_ec2)
│   └── configure-web.yml      # Playbook : installation et configuration de Nginx via SSM
├── bootstrap-backend/
│   ├── main.tf                # Bucket S3 (state Terraform) + bucket S3 (transfert Ansible/SSM)
│   └── outputs.tf             # Export du nom du bucket SSM
├── environments/
│   ├── staging/                # Root module — eu-west-3
│   ├── staging-eu-west-1/       # Root module — eu-west-1 (validation multi-région)
│   └── prod/                    # Root module — eu-west-3
│       ├── backend.hcl          # Config backend S3 (clé distincte par environnement)
│       ├── main.tf              # Appel au module "platform"
│       └── *.tfvars             # Variables (région, CIDR) par environnement
├── modules/
│   └── platform/
│       ├── main.tf              # VPC, subnets, IGW, route table, SG, EC2, S3, IAM
│       ├── variables.tf         
│       ├── outputs.tf           
│       └── versions.tf          
└── README.md





```


---

## Points techniques notables

**Isolation des states** : chaque environnement/région (`staging`, `staging-eu-west-1`, `prod`) possède sa propre clé de backend S3 — une erreur dans un environnement ne peut pas affecter le state d'un autre.

**Module réutilisable, pas de duplication de code** : la même définition d'infrastructure (`modules/platform`) est instanciée pour chaque environnement avec des paramètres différents (région, CIDR, nom), garantissant la cohérence entre staging et prod.

**Accès sans SSH** : la configuration des serveurs passe entièrement par AWS Systems Manager. Aucune paire de clés à distribuer, aucun port 22 ouvert, aucune IP publique nécessaire pour l'administration — seule une politique IAM (`AmazonSSMManagedInstanceCore`) attachée au rôle de l'instance autorise la connexion.

**Inventaire 100% dynamique** : aucune IP ni instance-id n'est écrite en dur. L'inventaire Ansible interroge l'API AWS à chaque exécution et regroupe automatiquement les instances par tags (`Role`, `Environment`) et par région — le playbook cible des groupes logiques (`role_web`), jamais des machines nommées.

**Validation multi-région avant généralisation** : l'environnement `staging-eu-west-1` sert de test de portabilité du code (aucune valeur régionale codée en dur, notamment le nommage des buckets S3) avant d'envisager une réplication de `prod` dans une seconde région pour la haute disponibilité.



---

## Nettoyage

Pour détruire l'infrastructure complètement, dans l'ordre (les environnements avant le backend) :

```bash
cd environments/staging && terraform destroy -var-file=staging.tfvars
cd ../staging-eu-west-1 && terraform destroy -var-file=staging.tfvars
cd ../prod && terraform destroy -var-file=prod.tfvars
cd ../../bootstrap-backend && terraform destroy
```


Si le destroy du bucket échoue (`BucketNotEmpty`, dû au versioning S3):

- Supprimer toutes les versions d'objets et les delete markers

```bash
aws s3api delete-objects \
  --bucket goai-tfstate-680319777993 \
  --delete "$(aws s3api list-object-versions \
    --bucket goai-tfstate-680319777993 \
    --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json)" 2>/dev/null

aws s3api delete-objects \
  --bucket goai-tfstate-680319777993 \
  --delete "$(aws s3api list-object-versions \
    --bucket goai-tfstate-680319777993 \
    --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json)" 2>/dev/null

```

- Relancer le destroy

```bash
terraform destroy
```

---

## Améliorations futures

- Automatiser l'enchaînement `terraform apply` -> `ansible-playbook` via un pipeline CI/CD (GitHub Actions).

- Répliquer l'environnement `prod` dans une seconde région pour la haute disponibilité (reprise après sinistre).

- Ajouter une supervision (Prometheus/Grafana) sur les instances EC2.



























