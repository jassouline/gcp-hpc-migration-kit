# Step 2 — Cloud Foundation: Isolated Project, Billing Credits, IAM & Quotas

When migrating simulation workloads (CFD, FEA, Thermal, Multiphysics) to Google Cloud, two issues cause 90% of first-time deployment failures:
1. **Insufficient IAM permissions** when engineers try to run Terraform / Cluster Toolkit inside a shared corporate project.
2. **Regional vCPU Quota limits** when launching a 512-core or 1,024-core Slurm job on a newly created Cloud Billing account.

This guide walks you through setting up a clean, isolated HPC environment using only public **Google Cloud Console** pages or **Google Cloud Shell**—even if this is your very first time using Google Cloud.

---

## 1. Why Create a Dedicated GCP Project for HPC?

Instead of deploying Slurm inside an existing project (which may host production apps, AI APIs, or sensitive data), **always create a dedicated project** (e.g., `my-company-hpc-cfd`):
- **Zero Blast Radius:** Your engineers can safely create and destroy Slurm clusters (`./ghpc deploy` / `./ghpc destroy`) without affecting any other company resources.
- **Unblocked Automation:** Google Cloud Cluster Toolkit (`ghpc`) automatically creates Service Accounts, IAM bindings, VPC networks, and Cloud Filestore shares. Granting your simulation lead `roles/owner` (or Project Editor + IAM Admin) **only on this isolated HPC project** prevents permission errors while keeping the rest of your organization locked down.
- **Shared Credits & Consolidated Billing:** Multiple projects can be linked to the **same Cloud Billing Account**. Any Promotional Credits (such as Google for Startups credits, PoC credits, or Enterprise commits) attached to your Billing Account are **automatically shared** with the new HPC project.

---

## 2. Automated Setup via Google Cloud Shell (2 Minutes)

1. Open [Google Cloud Console](https://console.cloud.google.com) as a Billing / Organization Administrator.
2. Click the **Activate Cloud Shell** icon (`>_`) in the top-right navigation bar.
3. Run our interactive project bootstrapper:

```bash
chmod +x 2-foundation/setup-hpc-project.sh
./2-foundation/setup-hpc-project.sh \
  --project-id "my-company-hpc-cfd" \
  --engineers "alice@example.com,bob@example.com"
```

### What `setup-hpc-project.sh` does automatically:
1. Detects your active **Billing Account ID** and **Organization ID** (or prompts you to pick one if you have several).
2. Creates the isolated project (`my-company-hpc-cfd`).
3. Links the project to your Billing Account so all HPC usage draws from your existing credits/billing.
4. Grants `roles/owner` on **this project only** to the specified simulation engineers.
5. Enables all required Google Cloud APIs (`compute.googleapis.com`, `file.googleapis.com`, `servicenetworking.googleapis.com`, `iam.googleapis.com`, `cloudresourcemanager.googleapis.com`).

---

## 3. Setting Up Cost Guardrails (Cloud Billing Budget Alerts)

Even though our Slurm blueprints use **Scale-to-Zero** (0 compute nodes running when idle), we strongly recommend setting a **Budget Alert** before running large 512+ core campaigns:

1. Go to **[Cloud Billing > Budgets & alerts](https://console.cloud.google.com/billing/budgets)**.
2. Click **Create Budget**:
   - **Name:** `HPC Simulation Monthly Budget Alert`
   - **Projects:** Select your new HPC project (`my-company-hpc-cfd`).
   - **Credits:** Keep *"Include discounts and promotions"* checked if you want to track net spend after credits, or **uncheck** it to track gross credit burn against your promotional credit pool.
3. Set threshold alerts at **50%**, **80%**, and **100%** and add your simulation engineers' email addresses under **Manage notifications**.

---

## 4. Understanding & Checking Google Cloud HPC Quotas (Crucial!)

### A. The "2x Quota Rule" When Hyper-Threading Is Disabled (`threads_per_core = 1`)

For CFD and FEA solvers (Ansys Fluent, OpenFOAM, Star-CCM+, Abaqus), **Hyper-Threading (Simultaneous Multithreading) should be disabled** so that every MPI rank runs on a dedicated physical core with full access to the L1/L2 cache and AVX-512 floating-point pipelines.

- On **C3**, **C3D**, and **C4** VMs:
  - `1 Physical Core = 2 nominal vCPUs`
  - When you set `threads_per_core: 1` (already configured in our blueprints), a `c3-standard-88` VM exposes **44 physical cores** to Linux and Slurm.
  - **However, Google Cloud Quota (`C3_CPUS`) is still metered on the nominal vCPU count (`88 vCPUs` per `c3-standard-88`)!**
- On **H3** VMs (`h3-standard-88`):
  - Hyper-Threading is disabled at the hardware level by default (`1 Physical Core = 1 vCPU`).
  - An `h3-standard-88` exposes **88 physical cores** and consumes **88 `H3_CPUS`** of quota.

#### Quota Quick Calculation Table

| Target Physical Cores for Solver | Using `c3-standard-88` (44 phy cores/node) | Nominal `C3_CPUS` Quota Required | Recommended Quota to Request (with buffer) | Using `h3-standard-88` (88 phy cores/node) | Nominal `H3_CPUS` Quota Required |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **128 physical cores** | 3 nodes (132 phy cores) | `264 C3_CPUS` | **`352 C3_CPUS`** | 2 nodes (176 phy cores) | `176 H3_CPUS` |
| **256 physical cores** | 6 nodes (264 phy cores) | `528 C3_CPUS` | **`704 C3_CPUS`** | 3 nodes (264 phy cores) | `264 H3_CPUS` |
| **512 physical cores** | 12 nodes (528 phy cores) | `1,056 C3_CPUS` | **`1,200 C3_CPUS`** | 6 nodes (528 phy cores) | `528 H3_CPUS` |
| **1,024 physical cores** | 24 nodes (1,056 phy cores) | `2,112 C3_CPUS` | **`2,400 C3_CPUS`** | 12 nodes (1,056 phy cores) | `1,056 H3_CPUS` |

---

### B. Why Projects Often Need a Quota Check Before Multi-Node Runs

Google Cloud projects enforce regional, per-machine-family vCPU quota limits (`C3_CPUS`, `H3_CPUS`, `C3D_CPUS`, `C4_CPUS`) to prevent unintended spend. Because default project quotas are often smaller than the vCPU count required by a multi-node HPC cluster, you should always verify your project's live regional quota before running `./ghpc deploy`.

**Before deploying your cluster**, run our self-service Readiness & Quota Checker in Cloud Shell:

```bash
chmod +x 2-foundation/check-gcp-hpc-readiness.sh
./2-foundation/check-gcp-hpc-readiness.sh \
  --project "my-company-hpc-cfd" \
  --cores 512 \
  --family C3 \
  --region europe-west1
```

This script will:
1. Query your **live regional quota** (`C3_CPUS`, `C3D_CPUS`, `H3_CPUS`, `C4_CPUS`) in the target region.
2. List the exact **zones** in that region where your chosen machine type is available.
3. Tell you immediately if your current quota is `[OK]` or `[INSUFFICIENT]`, and generate a **ready-to-paste Quota Increase justification** if needed.

---

### C. How to Request a Quota Increase in the Google Cloud Console (2 Minutes)

If `check-gcp-hpc-readiness.sh` indicates you need a higher quota:

1. Open **[IAM & Admin > Quotas & System Limits](https://console.cloud.google.com/iam-admin/quotas)** in your HPC project.
2. In the **Filter** bar, enter:
   - `Metric: C3_CPUS` *(or `H3_CPUS` / `C3D_CPUS`, and `C3_PREEMPTIBLE_CPUS` if using Spot VMs)*
   - `Dimension (Location): europe-west1` *(or your chosen region)*
3. Check the box next to the quota row and click **Edit Quotas** (top right).
4. Enter the target value recommended by `check-gcp-hpc-readiness.sh` (e.g., `1200` for a 512-core C3 cluster) and paste the generated justification into the **Request description** field.
5. Submit the request (automated quota reviews typically respond within minutes to 24–48 business hours; if you work with a Google Cloud Account Team or Partner, share the confirmation email with them to accelerate approval).
