"use strict";

(function () {
  const ALLOWED_SOURCES = new Set(["onprem", "aws-c6i", "aws-hpc6a", "azure-hbv3", "azure-fx"]);
  const ALLOWED_SOLVERS = new Set(["fluent", "starccm", "openfoam", "abaqus", "lsdyna"]);
  const ALLOWED_RAM_PROFILES = new Set(["standard", "highmem"]);
  const REGION_ZONES = {
    "europe-west1": "europe-west1-b",
    "europe-west4": "europe-west4-b",
    "europe-west3": "europe-west3-a",
    "europe-west9": "europe-west9-a",
    "us-central1": "us-central1-a",
    "us-east4": "us-east4-a"
  };

  const I18N = {
    en: {
      title: "Sim2GCP — HPC & CAE Simulation Sizer & Blueprint Generator",
      subtitle: "Migrate from On-Premise clusters, AWS ParallelCluster, or Azure CycleCloud to Google Cloud Slurm v6 in minutes.",
      configHeading: "1. Simulation & Source Profile",
      recHeading: "2. Recommended Google Cloud Architecture & Quotas",
      lblSource: "Current Source Environment",
      lblSolver: "Primary CAE / Simulation Solver",
      lblRamProfile: "Mesh Size / RAM Footprint per Core",
      lblCores: "Target Physical Cores per Simulation Run",
      hintCores: "Align with your solver license pack (e.g., 128, 256, 512, or 1024 physical cores).",
      lblRegion: "Target Google Cloud Region",
      hintRegion: "Select a geographic region supported by your target machine series.",
      lblProject: "Google Cloud Project ID",
      optSrcOnprem: "On-Premise Workstation / Cluster",
      optSrcAwsc6i: "AWS ParallelCluster — c6i / c7i (Intel Xeon)",
      optSrcAwshpc: "AWS ParallelCluster — hpc6a / hpc7a (AMD EPYC)",
      optSrcAzhb: "Azure CycleCloud — HBv3 / HBv4 (AMD EPYC)",
      optSrcAzfx: "Azure CycleCloud — FX / E-series (High RAM)",
      optSolFluent: "Ansys Fluent / CFX (CFD)",
      optSolStarccm: "Siemens Star-CCM+ (CFD)",
      optSolOpenfoam: "OpenFOAM / WRF (Memory-Bandwidth CFD)",
      optSolAbaqus: "Abaqus / Ansys Mechanical / COMSOL (FEA)",
      optSolLsdyna: "LS-DYNA / Radioss / Custom MPI",
      optRamStd: "Standard (<= 8 GB RAM / physical core)",
      optRamHigh: "High-Memory (> 8 GB RAM / physical core)",
      mLblMachine: "Recommended VM Type",
      mLblNodes: "Cluster Sizing",
      mLblQuota: "Required Regional Quota",
      mLblNet: "Interconnect & Elasticity",
      mValNet: "gVNIC + COMPACT",
      mSubNet: "Scale-to-Zero (0 VMs when idle)",
      hdrCli: "Step A — Check Regional Quota & Deploy from Google Cloud Shell",
      hdrYaml: "Step B — Customized Cluster Toolkit Blueprint (cluster.yaml)",
      hdrSbatch: "Step C — Ready-to-Run Slurm Submission Script (submit_job.sh)",
      btnCopyCli: "Copy Commands",
      btnCopyYaml: "Copy YAML",
      btnDlYaml: "Download cluster.yaml",
      btnCopySbatch: "Copy Script",
      btnDlSbatch: "Download submit_job.sh",
      copied: "Copied to clipboard!"
    },
    fr: {
      title: "Sim2GCP — Calculateur de Sizing HPC & Générateur de Blueprint Google Cloud",
      subtitle: "Migrez vos simulations depuis vos serveurs On-Premise, AWS ParallelCluster ou Azure CycleCloud vers Slurm v6 en quelques minutes.",
      configHeading: "1. Profil de Simulation & Environnement Source",
      recHeading: "2. Architecture Google Cloud & Quotas Recommandés",
      lblSource: "Environnement Source Actuel",
      lblSolver: "Solveur de Simulation Principal",
      lblRamProfile: "Taille de Maillage / Empreinte RAM par Cœur",
      lblCores: "Cœurs Physiques Visés par Run",
      hintCores: "Alignez sur vos packs de licences HPC (ex. 128, 256, 512 ou 1024 cœurs physiques).",
      lblRegion: "Région Google Cloud Cible",
      hintRegion: "Sélectionnez une région géographique proposant la famille de machines choisie.",
      lblProject: "ID du Projet Google Cloud",
      optSrcOnprem: "Serveur / Cluster On-Premise",
      optSrcAwsc6i: "AWS ParallelCluster — c6i / c7i (Intel Xeon)",
      optSrcAwshpc: "AWS ParallelCluster — hpc6a / hpc7a (AMD EPYC)",
      optSrcAzhb: "Azure CycleCloud — HBv3 / HBv4 (AMD EPYC)",
      optSrcAzfx: "Azure CycleCloud — Séries FX / E (Haute RAM)",
      optSolFluent: "Ansys Fluent / CFX (CFD)",
      optSolStarccm: "Siemens Star-CCM+ (CFD)",
      optSolOpenfoam: "OpenFOAM / WRF (CFD Bande Passante Mémoire)",
      optSolAbaqus: "Abaqus / Ansys Mechanical / COMSOL (FEA)",
      optSolLsdyna: "LS-DYNA / Radioss / Solveur MPI",
      optRamStd: "Standard (<= 8 Go RAM / cœur physique)",
      optRamHigh: "Haute Mémoire (> 8 Go RAM / cœur physique)",
      mLblMachine: "Instance GCP Recommandée",
      mLblNodes: "Dimensionnement Cluster",
      mLblQuota: "Quota Régional Requis",
      mLblNet: "Interconnexion & Élasticité",
      mValNet: "gVNIC + COMPACT",
      mSubNet: "Scale-to-Zero (0 VM au repos)",
      hdrCli: "Étape A — Vérifier le Quota Régional & Déployer depuis Cloud Shell",
      hdrYaml: "Étape B — Blueprint Cluster Toolkit Sur-Mesure (cluster.yaml)",
      hdrSbatch: "Étape C — Script de Soumission Slurm Prêt à l'Emploi (submit_job.sh)",
      btnCopyCli: "Copier les commandes",
      btnCopyYaml: "Copier le YAML",
      btnDlYaml: "Télécharger cluster.yaml",
      btnCopySbatch: "Copier le script",
      btnDlSbatch: "Télécharger submit_job.sh",
      copied: "Copié dans le presse-papiers !"
    }
  };

  let currentLang = "en";

  function sanitizeProjectId(raw) {
    const cleaned = String(raw || "")
      .toLowerCase()
      .replace(/[^a-z0-9-]/g, "")
      .slice(0, 30);
    return cleaned.length >= 6 ? cleaned : "my-company-hpc-cfd";
  }

  function clampInt(val, min, max, fallback) {
    const parsed = Number.parseInt(val, 10);
    if (Number.isNaN(parsed)) return fallback;
    return Math.min(max, Math.max(min, parsed));
  }

  function showToast(message) {
    const toast = document.getElementById("toast");
    if (!toast) return;
    toast.textContent = message;
    toast.classList.add("visible");
    window.setTimeout(function () {
      toast.classList.remove("visible");
    }, 1800);
  }

  function selectMachineSpec(source, solver, ramProfile) {
    if (ramProfile === "highmem" || solver === "abaqus" || source === "azure-fx") {
      return {
        family: "C3",
        quotaMetric: "C3_CPUS",
        machineType: "c3-highmem-176",
        phyCoresPerNode: 88,
        vcpusPerNode: 176,
        ramGbPerNode: 1408,
        threadsPerCore: 1,
        rationaleEn:
          "High-Memory profile selected: c3-highmem-176 provides 88 physical cores (with threads_per_core=1) and 1,408 GB DDR5 RAM (16 GB/physical core) with gVNIC networking.",
        rationaleFr:
          "Profil Haute-Mémoire sélectionné : c3-highmem-176 fournit 88 cœurs physiques (avec threads_per_core=1) et 1 408 Go de RAM DDR5 (16 Go/cœur physique) avec réseau gVNIC."
      };
    }

    if (solver === "openfoam" || source === "aws-hpc6a" || source === "azure-hbv3") {
      return {
        family: "H3",
        quotaMetric: "H3_CPUS",
        machineType: "h3-standard-88",
        phyCoresPerNode: 88,
        vcpusPerNode: 88,
        ramGbPerNode: 352,
        threadsPerCore: 1,
        rationaleEn:
          "Memory-bandwidth-bound CFD profile: h3-standard-88 provides 88 physical cores (Simultaneous Multithreading disabled by default) and 352 GB DDR5 memory.",
        rationaleFr:
          "Profil CFD intensif en bande passante mémoire : h3-standard-88 fournit 88 cœurs physiques (Simultaneous Multithreading désactivé par défaut) et 352 Go de mémoire DDR5."
      };
    }

    return {
      family: "C3",
      quotaMetric: "C3_CPUS",
      machineType: "c3-standard-88",
      phyCoresPerNode: 44,
      vcpusPerNode: 88,
      ramGbPerNode: 352,
      threadsPerCore: 1,
      rationaleEn:
        "Balanced CFD/Multiphysics profile: c3-standard-88 with threads_per_core=1 exposes 44 physical cores (Intel Xeon 4th Gen with AVX-512) and 352 GB DDR5 RAM (8 GB/physical core).",
      rationaleFr:
        "Profil CFD/Multiphysique équilibré : c3-standard-88 avec threads_per_core=1 expose 44 cœurs physiques (Intel Xeon 4e Gén avec AVX-512) et 352 Go de RAM DDR5 (8 Go/cœur physique)."
    };
  }

  function buildYamlBlueprint(projectId, region, zone, spec, nodesNeeded) {
    const deployName = "hpc-slurm-" + spec.family.toLowerCase();
    const lines = [
      "# Generated by Sim2GCP Interactive Sizer",
      "blueprint_name: " + deployName,
      "",
      "vars:",
      "  project_id: " + projectId,
      "  deployment_name: " + deployName,
      "  region: " + region,
      "  zone: " + zone,
      "",
      "deployment_groups:",
      "  - group: primary",
      "    modules:",
      "      - id: hpc_network",
      "        source: modules/network/vpc",
      "        settings:",
      "          network_name: $(vars.deployment_name)-net",
      "          mtu: 8896",
      "",
      "      - id: homefs",
      "        source: modules/file-system/filestore",
      "        use: [hpc_network]",
      "        settings:",
      "          filestore_tier: BASIC_HDD",
      "          size_gb: 1024",
      "          local_mount: /home",
      "",
      "      - id: compute_nodeset",
      "        source: community/modules/compute/schedmd-slurm-gcp-v6-nodeset",
      "        use: [hpc_network]",
      "        settings:",
      "          machine_type: " + spec.machineType,
      "          node_count_static: 0",
      "          node_count_dynamic_max: " + nodesNeeded
    ];

    if (spec.family !== "H3") {
      lines.push("          advanced_machine_features:");
      lines.push("            threads_per_core: " + spec.threadsPerCore);
    }

    lines.push(
      "          enable_placement: true",
      "          bandwidth_tier: gvnic_enabled",
      "          disk_type: pd-balanced",
      "          disk_size_gb: 100",
      "          allow_automatic_updates: false",
      "",
      "      - id: compute_partition",
      "        source: community/modules/compute/schedmd-slurm-gcp-v6-partition",
      "        use: [compute_nodeset]",
      "        settings:",
      "          partition_name: sim",
      "          is_default: true",
      "          exclusive: false",
      "          suspend_time: 300",
      "",
      "      - id: slurm_login",
      "        source: community/modules/scheduler/schedmd-slurm-gcp-v6-login",
      "        use: [hpc_network]",
      "        settings:",
      "          name_prefix: login",
      "          machine_type: n2-standard-4",
      "          enable_login_public_ips: true",
      "",
      "      - id: slurm_controller",
      "        source: community/modules/scheduler/schedmd-slurm-gcp-v6-controller",
      "        use: [hpc_network, homefs, slurm_login, compute_partition]",
      "        settings:",
      "          enable_controller_public_ips: true",
      "          enable_slurm_auth: true"
    );

    return lines.join("\n");
  }

  function buildSbatchScript(solver, nodesNeeded, phyCoresPerNode, targetCores) {
    const totalAllocated = nodesNeeded * phyCoresPerNode;
    const activeRanks = Math.min(totalAllocated, targetCores);
    let solverCmd = 'mpirun -np "' + activeRanks + '" --bind-to core ./my_solver -parallel';
    if (solver === "fluent") {
      solverCmd = [
        'export ANSYSLMD_LICENSE_FILE="1055@10.0.0.10"',
        'HOSTFILE="hosts_${SLURM_JOB_ID}.txt"',
        'scontrol show hostnames "${SLURM_JOB_NODELIST}" | awk -v t="${SLURM_NTASKS_PER_NODE}" \'{print $0":"t}\' > "${HOSTFILE}"',
        '/home/shared/ansys_inc/v242/fluent/bin/fluent 3ddp -g -t' + activeRanks + ' -cnf="${HOSTFILE}" -mpi=intel -pib.infiniband=off -i solve.jou'
      ].join("\n");
    } else if (solver === "openfoam") {
      solverCmd = [
        "decomposePar -force",
        "mpirun -np " + activeRanks + " --bind-to core simpleFoam -parallel",
        "reconstructPar -latestTime"
      ].join("\n");
    } else if (solver === "abaqus") {
      solverCmd = [
        'export ABAQUSLM_LICENSE_FILE="27000@10.0.0.10"',
        '/home/shared/SIMULIA/Commands/abaqus job=model input=model.inp cpus=' + activeRanks + ' mp_mode=mpi interactive'
      ].join("\n");
    }

    return [
      "#!/bin/bash",
      "#SBATCH --job-name=sim2gcp-" + solver,
      "#SBATCH --partition=sim",
      "#SBATCH --nodes=" + nodesNeeded,
      "#SBATCH --ntasks-per-node=" + phyCoresPerNode,
      "#SBATCH --exclusive",
      "#SBATCH --time=04:00:00",
      "#SBATCH --output=/home/%u/sim_%j.out",
      "",
      "set -euo pipefail",
      solverCmd
    ].join("\n");
  }

  function updateAll() {
    const sourceEl = document.getElementById("input-source");
    const solverEl = document.getElementById("input-solver");
    const ramEl = document.getElementById("input-ram-profile");
    const coresEl = document.getElementById("input-cores");
    const regionEl = document.getElementById("input-region");
    const projectEl = document.getElementById("input-project");

    const source = ALLOWED_SOURCES.has(sourceEl.value) ? sourceEl.value : "onprem";
    const solver = ALLOWED_SOLVERS.has(solverEl.value) ? solverEl.value : "fluent";
    const ramProfile = ALLOWED_RAM_PROFILES.has(ramEl.value) ? ramEl.value : "standard";
    const targetCores = clampInt(coresEl.value, 16, 4096, 512);
    let region = Object.prototype.hasOwnProperty.call(REGION_ZONES, regionEl.value) ? regionEl.value : "europe-west1";
    const projectId = sanitizeProjectId(projectEl.value);

    const spec = selectMachineSpec(source, solver, ramProfile);
    if (spec.family === "H3" && region !== "europe-west4" && region !== "us-central1") {
      region = region.startsWith("us-") ? "us-central1" : "europe-west4";
      regionEl.value = region;
    }
    const zone = REGION_ZONES[region];
    const nodesNeeded = Math.ceil(targetCores / spec.phyCoresPerNode);
    const totalPhyCores = nodesNeeded * spec.phyCoresPerNode;
    const totalRamGb = nodesNeeded * spec.ramGbPerNode;
    const quotaNeeded = nodesNeeded * spec.vcpusPerNode;
    const quotaRecommended = (nodesNeeded + 1) * spec.vcpusPerNode;

    document.getElementById("m-val-machine").textContent = spec.machineType;
    document.getElementById("m-sub-machine").textContent =
      spec.family === "H3"
        ? "SMT Off (" + spec.phyCoresPerNode + " phy cores/VM)"
        : "threads_per_core: 1 (" + spec.phyCoresPerNode + " phy cores/VM)";
    document.getElementById("m-val-nodes").textContent =
      currentLang === "fr"
        ? nodesNeeded + " Nœuds (" + totalPhyCores + " Cœurs)"
        : nodesNeeded + " Nodes (" + totalPhyCores + " Cores)";
    document.getElementById("m-sub-nodes").textContent = totalRamGb.toLocaleString() + " GB DDR5 RAM (" + zone + ")";
    document.getElementById("m-val-quota").textContent = quotaNeeded.toLocaleString() + " " + spec.quotaMetric;
    document.getElementById("m-sub-quota").textContent =
      (currentLang === "fr" ? "Recommandé : >= " : "Recommended: >= ") + quotaRecommended.toLocaleString() + " vCPUs";

    const warnBanner = document.getElementById("quota-warning-banner");
    if (currentLang === "fr") {
      warnBanner.textContent =
        "Règle de Quota vCPU (SMT désactivé) : Sur la série " +
        spec.family +
        ", " +
        nodesNeeded +
        " instances " +
        spec.machineType +
        " (" +
        totalPhyCores +
        " cœurs physiques) représentent " +
        quotaNeeded +
        " vCPUs nominaux de quota régional (" +
        spec.quotaMetric +
        " dans " +
        region +
        "). Vérifiez votre limite actuelle dans IAM & Admin > Quotas ou via check-gcp-hpc-readiness.sh avant le déploiement.";
    } else {
      warnBanner.textContent =
        "Regional vCPU Quota Rule (SMT Disabled): On the " +
        spec.family +
        " series, " +
        nodesNeeded +
        " x " +
        spec.machineType +
        " nodes (" +
        totalPhyCores +
        " physical cores) require " +
        quotaNeeded +
        " nominal vCPUs of regional quota (" +
        spec.quotaMetric +
        " in " +
        region +
        "). Verify your project's quota limit in IAM & Admin > Quotas or run check-gcp-hpc-readiness.sh before deploying.";
    }

    const rationaleBanner = document.getElementById("rationale-banner");
    rationaleBanner.textContent = currentLang === "fr" ? spec.rationaleFr : spec.rationaleEn;

    const deployName = "hpc-slurm-" + spec.family.toLowerCase();
    const cliText = [
      "# 1. Check your project's regional vCPU quota & zone availability",
      "./2-foundation/check-gcp-hpc-readiness.sh \\",
      "  --project " + projectId + " \\",
      "  --cores " + targetCores + " \\",
      "  --family " + spec.family + " \\",
      "  --region " + region,
      "",
      "# 2. Compile & deploy the Slurm v6 cluster from Google Cloud Shell",
      "./ghpc create cluster.yaml --vars project_id=" + projectId,
      "./ghpc deploy " + deployName + " --auto-approve"
    ].join("\n");

    document.getElementById("out-cli").textContent = cliText;
    document.getElementById("out-yaml").textContent = buildYamlBlueprint(projectId, region, zone, spec, nodesNeeded);
    document.getElementById("out-sbatch").textContent = buildSbatchScript(solver, nodesNeeded, spec.phyCoresPerNode, targetCores);
  }

  function applyLang(lang) {
    currentLang = lang === "fr" ? "fr" : "en";
    document.documentElement.lang = currentLang;
    const t = I18N[currentLang];
    const map = {
      "ui-title": t.title,
      "ui-subtitle": t.subtitle,
      "ui-config-heading": t.configHeading,
      "ui-rec-heading": t.recHeading,
      "lbl-source": t.lblSource,
      "lbl-solver": t.lblSolver,
      "lbl-ram-profile": t.lblRamProfile,
      "lbl-cores": t.lblCores,
      "hint-cores": t.hintCores,
      "lbl-region": t.lblRegion,
      "hint-region": t.hintRegion,
      "lbl-project": t.lblProject,
      "opt-src-onprem": t.optSrcOnprem,
      "opt-src-awsc6i": t.optSrcAwsc6i,
      "opt-src-awshpc": t.optSrcAwshpc,
      "opt-src-azhb": t.optSrcAzhb,
      "opt-src-azfx": t.optSrcAzfx,
      "opt-sol-fluent": t.optSolFluent,
      "opt-sol-starccm": t.optSolStarccm,
      "opt-sol-openfoam": t.optSolOpenfoam,
      "opt-sol-abaqus": t.optSolAbaqus,
      "opt-sol-lsdyna": t.optSolLsdyna,
      "opt-ram-std": t.optRamStd,
      "opt-ram-high": t.optRamHigh,
      "m-lbl-machine": t.mLblMachine,
      "m-lbl-nodes": t.mLblNodes,
      "m-lbl-quota": t.mLblQuota,
      "m-lbl-net": t.mLblNet,
      "m-val-net": t.mValNet,
      "m-sub-net": t.mSubNet,
      "hdr-cli": t.hdrCli,
      "hdr-yaml": t.hdrYaml,
      "hdr-sbatch": t.hdrSbatch,
      "btn-copy-cli": t.btnCopyCli,
      "btn-copy-yaml": t.btnCopyYaml,
      "btn-dl-yaml": t.btnDlYaml,
      "btn-copy-sbatch": t.btnCopySbatch,
      "btn-dl-sbatch": t.btnDlSbatch
    };

    Object.keys(map).forEach(function (id) {
      const el = document.getElementById(id);
      if (el) el.textContent = map[id];
    });

    document.getElementById("btn-lang-en").classList.toggle("btn-primary", currentLang === "en");
    document.getElementById("btn-lang-fr").classList.toggle("btn-primary", currentLang === "fr");
    updateAll();
  }

  function copyPreContent(elementId) {
    const el = document.getElementById(elementId);
    if (!el || !navigator.clipboard) return;
    navigator.clipboard.writeText(el.textContent || "").then(function () {
      showToast(I18N[currentLang].copied);
    });
  }

  function downloadTextFile(filename, content, mimeType) {
    const blob = new Blob([content], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.setAttribute("href", url);
    link.setAttribute("download", filename);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }

  document.addEventListener("DOMContentLoaded", function () {
    const inputs = [
      "input-source",
      "input-solver",
      "input-ram-profile",
      "input-cores",
      "input-region",
      "input-project"
    ];
    inputs.forEach(function (id) {
      const el = document.getElementById(id);
      if (el) {
        el.addEventListener("input", updateAll);
        el.addEventListener("change", updateAll);
      }
    });

    document.getElementById("btn-lang-en").addEventListener("click", function () {
      applyLang("en");
    });
    document.getElementById("btn-lang-fr").addEventListener("click", function () {
      applyLang("fr");
    });

    document.getElementById("btn-copy-cli").addEventListener("click", function () {
      copyPreContent("out-cli");
    });
    document.getElementById("btn-copy-yaml").addEventListener("click", function () {
      copyPreContent("out-yaml");
    });
    document.getElementById("btn-copy-sbatch").addEventListener("click", function () {
      copyPreContent("out-sbatch");
    });

    document.getElementById("btn-dl-yaml").addEventListener("click", function () {
      const content = document.getElementById("out-yaml").textContent || "";
      downloadTextFile("cluster.yaml", content, "text/yaml;charset=utf-8");
    });
    document.getElementById("btn-dl-sbatch").addEventListener("click", function () {
      const content = document.getElementById("out-sbatch").textContent || "";
      downloadTextFile("submit_job.sh", content, "text/x-shellscript;charset=utf-8");
    });

    updateAll();
  });
})();
