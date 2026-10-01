# Sim2GCP — Kit Clé en Main de Migration HPC & Simulation (CFD / FEA) vers Google Cloud

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Validate Blueprints & Scripts](https://github.com/jassouline/gcp-hpc-migration-kit/actions/workflows/validate.yml/badge.svg)](https://github.com/jassouline/gcp-hpc-migration-kit/actions/workflows/validate.yml)
[![Cluster Toolkit](https://img.shields.io/badge/Google_Cloud-Cluster_Toolkit_v1.73+-4285F4?logo=googlecloud&logoColor=white)](https://github.com/GoogleCloudPlatform/cluster-toolkit)
[![Scheduler: Slurm v6](https://img.shields.io/badge/Scheduler-Slurm_v6-008080)](https://slurm.schedmd.com/)

> **🇬🇧 English version available here :** [**README.md**](./README.md)  
> **🌐 Calculateur Interactif de Sizing & Générateur de Blueprint :** [**https://jassouline.github.io/gcp-hpc-migration-kit/**](https://jassouline.github.io/gcp-hpc-migration-kit/) *(ou ouvrez [`docs/index.html`](./docs/index.html) en local)*.

**Sim2GCP (`gcp-hpc-migration-kit`)** est un kit de migration en libre-service conçu pour les **équipes d'ingénierie, physiciens, chercheurs R&D et ingénieurs calculs** exécutant des simulations de mécanique des fluides (CFD), d'éléments finis (FEA), de thermique ou de multiphysique (**Ansys Fluent / CFX / Mechanical, OpenFOAM, Siemens Star-CCM+, Dassault Abaqus, COMSOL, LS-DYNA**).

Que vous migriez depuis **des serveurs de calcul locaux (on-premise) saturés**, **AWS ParallelCluster** ou **Azure CycleCloud**, ce dépôt fournit l'ensemble des scripts, vérificateurs de quotas, blueprints Slurm pré-optimisés et guides d'interfaçage de licences (BYOL) permettant de déployer un **cluster HPC élastique Scale-to-Zero sur Google Cloud en moins de 30 minutes** — uniquement depuis **Google Cloud Shell** (sans aucune installation sur votre poste).

---

## Pourquoi utiliser ce kit ?

Les documentations cloud généralistes supposent souvent que vous disposez d'une équipe DevOps/Infra dédiée. En pratique, la migration de charges de calcul scientifique bloque presque toujours sur **4 points précis** que ce kit résout nativement :

1. **« Quel est le profil exact de nos serveurs actuels et quelle machine Google Cloud choisir ? »**  
   → Résolu par [`1-assess/hpc-workload-profiler.sh`](./1-assess/hpc-workload-profiler.sh), un script Bash autonome (sans dépendance ni droit `root`) qui s'exécute sur votre serveur local, votre instance AWS (`c6i`, `c7i`, `hpc6a`, `hpc7a`) ou Azure (`HBv3`, `HBv4`), mesure la saturation CPU/RAM réelle par cœur pendant un calcul, et recommande la famille GCP optimale (**C3**, **C3D**, **H3** ou **C4**).
2. **« Comment isoler notre projet HPC, rattacher nos crédits/facturation et éviter les erreurs de quotas au déploiement ? »**  
   → Résolu par [`2-foundation/setup-hpc-project.sh`](./2-foundation/setup-hpc-project.sh) et [`2-foundation/check-gcp-hpc-readiness.sh`](./2-foundation/check-gcp-hpc-readiness.sh), qui vérifient vos quotas vCPU régionaux réels (`C3_CPUS`, `H3_CPUS`, `C3D_CPUS`), listent les zones offrant la série de machines choisie, et génèrent un texte de justification prêt à copier-coller si le quota actuel de votre projet est inférieur à la taille cible de votre cluster.
3. **« Comment configurer Slurm avec Hyper-Threading désactivé, Placement Compact, réseau gVNIC et Scale-to-Zero (0 € au repos) ? »**  
   → Résolu par les blueprints YAML clés en main dans [`3-blueprints/`](./3-blueprints/), pré-configurés pour **Cloud HPC Toolkit (`ghpc`)** avec une partition à la demande et une **partition Spot VMs**.
4. **« Comment relier notre serveur de licences FlexLM / RLM (Ansys, Star-CCM+, Abaqus...) et lancer nos jobs MPI multi-nœuds ? »**  
   → Résolu par [`4-licensing-and-jobs/BYOL_LICENSING_GUIDE.md`](./4-licensing-and-jobs/BYOL_LICENSING_GUIDE.md) et les [templates `sbatch` prêts à l'emploi](./4-licensing-and-jobs/sbatch-templates/).

---

## Table de Correspondance : On-Prem, AWS ou Azure → Google Cloud

| Profil de Simulation | Solveurs Typiques | Équivalent On-Prem | Équivalent AWS | Équivalent Azure | Machine GCP Recommandée | Cœurs Physiques (`threads_per_core=1`) | RAM par Nœud | Bande Passante Réseau |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **CFD & Multiphysique Équilibrée** | Ansys Fluent, CFX, Star-CCM+, SU2 | Bi-Xeon Gold/Platinum (32–64c) | `c6i.24xlarge` / `c7i.24xlarge` | `Standard_F72s_v2` / `FX48mds` | **`c3-standard-88`** *(ou `c3-standard-176`)* | **44 cœurs** *(ou 88 cœurs)* | 352 Go *(ou 704 Go)* | Jusqu'à 200 Gbps (Tier_1 / gVNIC) |
| **CFD intensive en Bande Passante Mémoire** | OpenFOAM, WRF, LES | AMD EPYC Milan-X / Xeon Max | `hpc6a.48xlarge` | `Standard_HB120rs_v3` (`HBv3`) | **`h3-standard-88`** | **88 cœurs physiques** *(HT désactivé nativement)* | 352 Go (DDR5 8 canaux) | Jusqu'à 200 Gbps |
| **Haute Densité de Cœurs / Scaling** | Crash Explicite (LS-DYNA, Radioss), Dynamique Moléculaire | Bi-AMD EPYC 9654 (90–128c) | `hpc7a.96xlarge` | `Standard_HB176rs_v4` (`HBv4`) | **`c3d-standard-180`** | **90 cœurs** | 720 Go | Jusqu'à 200 Gbps |
| **FEA & Électromagnétisme (Haute RAM)** | Ansys Mechanical, Abaqus Standard, COMSOL, HFSS | Serveurs Haute RAM (512 Go–1,5 To) | `r6i.32xlarge` / `hpc6id.32xlarge` | `Standard_E96s_v5` / `HX176rs` | **`c3-highmem-88`** *(ou `c3-highmem-176`)* | **44 cœurs** *(ou 88 cœurs)* | 704 Go *(ou 1 408 Go)* | Jusqu'à 200 Gbps |

> [!IMPORTANT]
> **Désactivez toujours l'Hyper-Threading (SMT) pour vos solveurs MPI :**  
> Sur le Cloud, 1 cœur physique correspond généralement à 2 vCPUs logiques (sauf sur la gamme `H3` où 1 vCPU = 1 cœur physique). Tous nos blueprints dans [`3-blueprints/`](./3-blueprints/) configurent `threads_per_core: 1` pour garantir que chaque processus MPI dispose d'un cœur physique entier et de 100 % des unités vectorielles AVX-512. **Attention : côté quota GCP (`C3_CPUS`, `C3D_CPUS`), Google Cloud comptabilise toujours le nombre nominal de vCPUs de la machine** (ex. une `c3-standard-88` avec `threads_per_core: 1` expose 44 cœurs physiques à Slurm et consomme 88 `C3_CPUS` de quota).
> - **Note sur la disponibilité régionale :** Consultez la [documentation officielle des régions et zones Compute Engine](https://cloud.google.com/compute/docs/regions-zones#available) ou exécutez [`2-foundation/check-gcp-hpc-readiness.sh`](./2-foundation/check-gcp-hpc-readiness.sh) pour lister les zones proposant les instances `C3`, `C3D`, `H3` ou `C4` dans votre région cible.

---

## Démarrage Rapide en 4 Étapes (30 Minutes)

### Étape 1 — Profiler votre serveur actuel ou instance AWS/Azure (5 min)

Copiez [`1-assess/hpc-workload-profiler.sh`](./1-assess/hpc-workload-profiler.sh) sur votre serveur de calcul actuel et lancez-le (idéalement pendant qu'une simulation représentative tourne) :

```bash
chmod +x 1-assess/hpc-workload-profiler.sh
./1-assess/hpc-workload-profiler.sh -d 60 -i 2
```

Ce script ne nécessite **aucun droit `root`** et génère un rapport Markdown complet (`hpc_profile_<hostname>_<timestamp>.md`) incluant :
- La détection automatique de l'environnement source (Serveur physique Dell/HP/Supermicro, AWS EC2 ou Azure VM).
- Le modèle exact de CPU, la topologie NUMA, le support AVX2/AVX-512 et la saturation cœur par cœur.
- La recommandation automatique de l'instance GCP cible (`c3-standard-88`, `c3-highmem-88`, `h3-standard-88`, `c3d-standard-180`) et le quota vCPU à prévoir.

---

### Étape 2 — Préparer un projet GCP isolé & Vérifier vos Quotas (10 min)

Ouvrez **[Google Cloud Shell](https://shell.cloud.google.com)** depuis votre navigateur et clonez ce dépôt :

```bash
git clone https://github.com/jassouline/gcp-hpc-migration-kit.git
cd gcp-hpc-migration-kit
```

1. **Créer un projet HPC isolé et le rattacher à votre compte de facturation / crédits :**
   ```bash
   chmod +x 2-foundation/setup-hpc-project.sh
   ./2-foundation/setup-hpc-project.sh --project-id mon-projet-hpc-cfd
   ```
   *(Consultez [`2-foundation/GUIDE_PROJECT_IAM_QUOTAS.md`](./2-foundation/GUIDE_PROJECT_IAM_QUOTAS.md) si vous débutez sur GCP et souhaitez savoir où trouver votre Billing Account ID, créer des alertes de budget et donner accès à votre équipe).*

2. **Vérifier vos quotas régionaux et la disponibilité des zones AVANT de déployer :**
   > [!WARNING]
   > Les projets Google Cloud appliquent des quotas régionaux par famille de machines (`C3_CPUS`, `H3_CPUS`, `C3D_CPUS`) qui varient selon votre projet et votre compte de facturation. Exécutez systématiquement ce script de vérification avant de déployer un cluster multi-nœuds afin de vérifier que votre quota couvre le nombre de nœuds cible !

   ```bash
   chmod +x 2-foundation/check-gcp-hpc-readiness.sh
   ./2-foundation/check-gcp-hpc-readiness.sh --project mon-projet-hpc-cfd --cores 512 --family C3 --region europe-west1
   ```

---

### Étape 3 — Déployer le cluster Slurm v6 avec Cluster Toolkit (10 min)

Depuis **Cloud Shell**, compilez et déployez le blueprint correspondant à votre besoin (par exemple [`3-blueprints/cfd-c3-slurm.yaml`](./3-blueprints/cfd-c3-slurm.yaml)) :

```bash
# 1. Compilation binaire de Cluster Toolkit (si absent de Cloud Shell)
if [ ! -f ./ghpc ]; then
  git clone --branch v1.73.0 --depth 1 https://github.com/GoogleCloudPlatform/cluster-toolkit.git /tmp/cluster-toolkit
  (cd /tmp/cluster-toolkit && make)
  cp /tmp/cluster-toolkit/ghpc ./ghpc
fi

# 2. Génération du dossier de déploiement Terraform
./ghpc create 3-blueprints/cfd-c3-slurm.yaml \
  --vars project_id="$(gcloud config get-value project)" \
  --vars region="europe-west1" \
  --vars zone="europe-west1-c"

# 3. Provisionnement du VPC, du partage NFS Filestore (/home) et de Slurm
./ghpc deploy hpc-slurm-c3 --auto-approve
```

Une fois déployé :
- **0 nœud de calcul n'est allumé au repos** (0 €/h de compute entre deux campagnes de simulation).
- Connectez-vous au nœud de login Slurm :
  ```bash
  gcloud compute ssh hpc-slurm-c3-login-001 --zone="europe-west1-c" --tunnel-through-iap
  ```

---

### Étape 4 — Connecter le serveur de licences & Soumettre vos calculs (5 min)

1. Suivez [`4-licensing-and-jobs/BYOL_LICENSING_GUIDE.md`](./4-licensing-and-jobs/BYOL_LICENSING_GUIDE.md) pour relier votre **serveur de licences FlexLM / RLM** :
   - **Option A (PoC immédiat en 2 min sans toucher au pare-feu d'entreprise) :** Tunnel SSH inversé depuis votre station de travail vers le nœud de login Slurm.
   - **Option B (Production) :** Tunnel Cloud VPN Site-à-Site avec ports TCP figés.
   - **Option C (Hébergé sur GCP) :** Hébergement d'un pack de licences sur une micro-VM GCP à IP interne fixe.
2. Utilisez les scripts modèles dans [`4-licensing-and-jobs/sbatch-templates/`](./4-licensing-and-jobs/sbatch-templates/) pour soumettre vos calculs :
   ```bash
   sbatch submit_ansys_fluent.sh
   squeue -u $USER
   ```

---

## Destruction complète de l'infrastructure

Pour supprimer intégralement le cluster (Filestore NFS, contrôleur Slurm, réseau VPC) à la fin d'une campagne :

```bash
./ghpc destroy hpc-slurm-c3 --auto-approve
```
