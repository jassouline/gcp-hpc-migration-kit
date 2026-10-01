# Step 4 — Bring Your Own License (BYOL) Connectivity Guide for CAE Solvers

Commercial engineering solvers (**Ansys Fluent / CFX / Mechanical, Siemens Star-CCM+, Dassault Abaqus, COMSOL, Altair HyperWorks**) rely on network license managers—most commonly **FlexNet Publisher (FlexLM)** or **Reprise License Manager (RLM)**—to check out HPC pack tokens when an MPI job starts.

Because Google Cloud compute nodes spin up dynamically inside a private VPC (`hpc-slurm-*-net`), they need network reachability to your license server. Below are the **three proven patterns** ordered from fastest PoC setup to permanent production setup.

---

## Mandatory First Step: Pin Dynamic Vendor Daemon Ports in `license.lic`

By default, FlexLM uses **1 static port** (e.g., `1055` for Ansys `lmgrd`, `1999` for Star-CCM+, `27000` for Abaqus) plus **1 random high TCP port** chosen at startup for the vendor daemon (`ansyslmd`, `cdlmd`, `abaquslm`). Random ports cannot traverse firewalls or SSH tunnels reliably.

Open your `license.lic` file on your license server and **pin the vendor daemon port** before restarting `lmgrd`:

### Example for Ansys (`license.lic`)
```text
SERVER my-license-server 001122334455 1055
VENDOR ansyslmd PORT=1056
USE_SERVER
```
*(If you also run the Ansys Licensing Interconnect, its default port is TCP `2325`.)*

### Example for Siemens Star-CCM+ (`license.dat`)
```text
SERVER my-license-server 001122334455 1999
VENDOR cdlmd PORT=2099
USE_SERVER
```

---

## Pattern A — Fast PoC via Reverse SSH Port Forwarding (2 Minutes, Zero Firewall Change)

If you want to benchmark your solver on Google Cloud **today** without waiting for corporate IT to configure a Site-to-Site VPN, you can project your local on-premise license server ports onto the Slurm Controller / Login node over an outbound IAP SSH tunnel:

1. On your Slurm Login node (`hpc-slurm-c3-login-001`), verify `GatewayPorts clientspecified` is enabled in `/etc/ssh/sshd_config` (or forward via the controller's internal IP).
2. From an on-premise workstation that can reach your local license server (`ONPREM_LIC_IP`, e.g., `192.168.1.50`), run:

```bash
# Forward TCP 1055, 1056, and 2325 from the Slurm Login Node back to your on-prem FlexLM server
gcloud compute ssh hpc-slurm-c3-login-001 \
  --zone="europe-west1-c" \
  --tunnel-through-iap \
  -- -N \
  -R 0.0.0.0:1055:192.168.1.50:1055 \
  -R 0.0.0.0:1056:192.168.1.50:1056 \
  -R 0.0.0.0:2325:192.168.1.50:2325
```

3. In your Slurm `sbatch` script, point the solver to the internal IP of `hpc-slurm-c3-login-001`:
```bash
export ANSYSLMD_LICENSE_FILE="1055@hpc-slurm-c3-login-001"
export ANSYSLI_SERVERS="2325@hpc-slurm-c3-login-001"
```

---

## Pattern B — Production Site-to-Site Cloud VPN (HA VPN)

For permanent production use with an on-premise license server:

1. In the Google Cloud Console, go to **[Network Connectivity > VPN](https://console.cloud.google.com/hybrid/vpn/list)** and create a **Cloud VPN** attached to your HPC VPC (`hpc-slurm-c3-net`).
2. Advertise the HPC VPC subnet (`10.0.0.0/20`) to your on-premise router/firewall and allow TCP traffic from `10.0.0.0/20` to your license server IP on your pinned ports (`1055`, `1056`, `2325`).
3. Verify connectivity from the Slurm login node:
```bash
nc -zv <ONPREM_LICENSE_SERVER_IP> 1055
nc -zv <ONPREM_LICENSE_SERVER_IP> 1056
```

---

## Pattern C — Hosting a Dedicated License Server VM on Google Cloud

If you have multiple HPC license packs (or want 0 ms license checkout latency inside the cloud VPC without a VPN), you can re-host one license pack onto a lightweight Google Cloud VM inside the HPC VPC:

```bash
# 1. Reserve a static internal IP in the HPC VPC
gcloud compute addresses create hpc-license-ip \
  --region="europe-west1" \
  --subnet="hpc-slurm-c3-net-sub"

# 2. Create a persistent lightweight VM for FlexLM
gcloud compute instances create hpc-license-server \
  --zone="europe-west1-c" \
  --machine-type="e2-medium" \
  --network="hpc-slurm-c3-net" \
  --subnet="hpc-slurm-c3-net-sub" \
  --private-network-ip="hpc-license-ip" \
  --image-family="rocky-linux-8" \
  --image-project="rocky-linux-cloud" \
  --boot-disk-size="50GB"
```

Once created, run `ip link show eth0` inside `hpc-license-server` to retrieve its persistent MAC address (HostID) and generate your license file in your vendor's customer portal.
