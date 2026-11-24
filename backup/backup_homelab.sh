#!/usr/bin/env bash
# =============================================================================
#  Home Lab Backups
#  One-shot + rerunnable backup of the homelab to the external drive.
#
#  Run:   bash backup_homelab.sh
#  From:  any git-bash / WSL bash terminal on THIS PC (Windows).
#
#  What it backs up
#    01_windows  -> this PC: hermes-first-task (docs, scripts, diagrams,
#                   manifests, CA cert) + extra paths listed below
#    02_pve      -> Proxmox node 172.16.0.11: /etc/pve (guest configs,
#                   users, storage, sdn, firewall), networking, host keys, crons
#    03_vm101    -> Docker host 172.16.0.157: cloud-security compose + init
#                   seeds, and a listing of containers/volumes
#    04_k3s      -> cert-manager CA private keys (needed to restore/issue certs)
#
#  Output:   I:/backups/Home Lab/<timestamp>_snapshot/  (prunes to N snapshots)
#  Log:       <snapshot>/backup.log  and  tail of MANIFEST.txt
# =============================================================================
set -uo pipefail

# --- Tune these --------------------------------------------------------------
TARGET_ROOT="/i/backups/Home Lab"          # MSYS path to I:\backups\Home Lab
KEEP_SNAPSHOTS=3                            # prune older than this many
SSH_KEY="C:/Users/Cloud-Sec/.ssh/hermes-pve"
PVE_HOST="172.16.0.11"; PVE_USER="hermes-admin"
CLOUDSEC_HOST="172.16.0.210"; CLOUDSEC_USER="root"
VM101_HOST="172.16.0.157"; VM101_USER="cloudsec"
ZIMAOS_HOST="172.16.0.15"; ZIMAOS_USER="cloudsec"; ZIMAOS_DIR="/DATA/backups"
ZIMAOS_KEY="C:/Users/Cloud-Sec/.ssh/homelab_mgmt"

# Extra Windows sources copied into 01_windows (beyond hermes-first-task)
EXTRA_WINDOWS=(
  "C:/Users/Cloud-Sec/.ssh/hermes-pve"            # ssh key (passwordless restore)
  "C:/Users/Cloud-Sec/hermes-first-task/homelab-ca.crt"
  "C:/Users/Cloud-Sec/Noel_Masanga_CV_Optimised_v4.docx"
  "C:/Users/Cloud-Sec/Desktop/Noel_Masanga_CV_v6_2page.docx"
  "C:/Users/Cloud-Sec/Noel_LinkedIn_Edit_Pack.docx"
)
# =============================================================================

TS=$(date +%Y%m%d-%H%M%S)
DEST="$TARGET_ROOT/${TS}_snapshot"
mkdir -p "$DEST/"{01_windows,02_pve,03_vm101,04_k3s,05_cloudsec}
: > "$DEST/backup.log"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$DEST/backup.log"; }
SSH(){ ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=6 "$@"; }
SSHP(){ ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=6 "$1" "$2"; }

log "== Home Lab backup starting -> $DEST =="

# --- 1. Windows PC -----------------------------------------------------------
log "Copying Windows configs/docs..."
# cp -a is reliable under MSYS (robocopy flag-mangling is a trap here)
mkdir -p "$DEST/01_windows/hermes-first-task"
cp -a "C:/Users/Cloud-Sec/hermes-first-task"/. "$DEST/01_windows/hermes-first-task"/ 2>/dev/null
count=$(find "$DEST/01_windows/hermes-first-task" -type f 2>/dev/null | wc -l)
log "  $count config/doc files copied"
i=1
for p in "${EXTRA_WINDOWS[@]}"; do
  if [ -e "$p" ]; then cp -a "$p" "$DEST/01_windows/extra_$i" 2>/dev/null; log "  + $(basename "$p")"; fi
  i=$((i+1))
done

# --- 2. Proxmox node ---------------------------------------------------------
log "Pulling PVE node configs..."
# config tree: /etc/pve (fuse, archive via tar), plus OS-level files
tar_pve='sudo tar czf - -C / \
  etc/pve \
  etc/network \
  etc/hosts etc/hostname \
  etc/ssh/ssh_host_*_key* \
  etc/default/grub \
  2>/dev/null'
SSHP "$PVE_USER@$PVE_HOST" "$tar_pve" > "$DEST/02_pve/pve-node.tar.gz" 2>/dev/null
# crontab / pve jobs
SSHP "$PVE_USER@$PVE_HOST" 'sudo crontab -l 2>/dev/null; echo "---UPTIME---"; uptime' \
  > "$DEST/02_pve/node-state.txt" 2>/dev/null
# store the guest config excavating in plain tar too (redundant, readable copy)
SSHP "$PVE_USER@$PVE_HOST" 'sudo tar czf - -C /etc/pve qemu-server lxc' \
  > "$DEST/02_pve/guest-configs.tar.gz" 2>/dev/null
log "  PVE node configs saved"

# --- 3. VM 101 (Docker host) -------------------------------------------------
log "Pulling VM 101 docker configs..."
mkdir -p "$DEST/03_vm101"
# safe pull of the compose tree + init seeds
SSHP "$VM101_USER@$VM101_HOST" 'tar czf - -C "$HOME" cloud-security' \
  > "$DEST/03_vm101/docker-stacks.tar.gz" 2>/dev/null
SSHP "$VM101_USER@$VM101_HOST" \
  'echo "--- CONTAINERS ---"; docker ps --format "{{.Names}} | {{.Image}} | {{.Status}}"; echo; echo "--- DOCKER VOLUMES ---"; docker volume ls; echo; echo "--- COMPOSE ---"; find ~/cloud-security -maxdepth 2 -name "compose*.yml" -o -name "*.yaml"' \
  > "$DEST/03_vm101/docker-inventory.txt" 2>/dev/null
log "  VM 101 docker stacks saved"

# --- 4. cert-manager CA private keys -----------------------------------------
log "Pulling cert-manager CA secrets..."
SSHP "$PVE_USER@$PVE_HOST" \
  'sudo /usr/sbin/pct exec 111 -- sh -c "KUBECONFIG=/etc/rancher/k3s/k3s.yaml /usr/local/bin/kubectl -n cert-manager get secret homelab-ca-key-pair -o yaml"' \
  > "$DEST/04_k3s/cert-manager-ca-secrets.yaml" 2>/dev/null
sz=$(wc -c < "$DEST/04_k3s/cert-manager-ca-secrets.yaml" 2>/dev/null)
if [ "${sz:-0}" -gt 50 ]; then log "  CA secrets exported ($sz bytes)"; else log "  WARN: CA export empty (node/k3s unreachable)"; fi

# --- 5. CloudSec node (standalone) ------------------------------------------
log "Pulling CloudSec node configs..."
SSHP "$CLOUDSEC_USER@$CLOUDSEC_HOST" 'tar czf - -C / \
  etc/pve etc/network etc/hosts etc/hostname etc/timezone \
  2>/dev/null' > "$DEST/05_cloudsec/cloudsec-node.tar.gz" 2>/dev/null
SSHP "$CLOUDSEC_USER@$CLOUDSEC_HOST" 'pveversion 2>/dev/null; echo "---UPTIME---"; uptime' \
  > "$DEST/05_cloudsec/state.txt" 2>/dev/null
log "  CloudSec node configs saved"

# --- Manifest ----------------------------------------------------------------
log "Writing MANIFEST..."
{
  echo "Home Lab backup snapshot: $TS"
  echo "Started : $(date)"
  du -sh "$DEST" 2>/dev/null | awk '{print "Total   :", $1}'
  echo
  echo "PVE node     : $PVE_HOST  (02_pve)"
  echo "VM 101 docker: $VM101_HOST (03_vm101)"
  echo "CloudSec     : $CLOUDSEC_HOST (05_cloudsec)"
  echo "cert-manager CA : 04_k3s"
  echo
  echo "--- PVE guests (cfg) ---"
  SSHP "$PVE_USER@$PVE_HOST" 'ls /etc/pve/qemu-server/ /etc/pve/lxc/' 2>/dev/null
  echo
  echo "--- Windows: hermes-first-task (top level) ---"
  ls "C:/Users/Cloud-Sec/hermes-first-task" 2>/dev/null
} > "$DEST/MANIFEST.txt" 2>/dev/null

log "Backup complete."

# --- Push snapshot to ZimaOS (.15) over SSH key --------------------------------
log "Pushing snapshot to ZimaOS ($ZIMAOS_USER@$ZIMAOS_HOST:$ZIMAOS_DIR)..."
if tar czf - -C "$TARGET_ROOT" "$(basename "$DEST")" 2>/dev/null | \
   ssh -i "$ZIMAOS_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no \
       "$ZIMAOS_USER@$ZIMAOS_HOST" "tar xzf - -C $ZIMAOS_DIR"; then
  REMOTE_SZ=$(ssh -i "$ZIMAOS_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no \
    "$ZIMAOS_USER@$ZIMAOS_HOST" "du -sh $ZIMAOS_DIR/$(basename "$DEST") 2>/dev/null | awk '{print \$1}'")
  log "  pushed to ZimaOS: $ZIMAOS_DIR/$(basename "$DEST") (${REMOTE_SZ:-?})"
else
  log "  WARN: ZimaOS push failed (is .15 up? key authorized?)"
fi
tail -n +1 "$DEST/MANIFEST.txt" 2>/dev/null | head -20

# --- prune old snapshots -------------------------------------------------------
cd "$TARGET_ROOT" 2>/dev/null || exit 0
mapfile -t snaps < <(ls -d ./*_snapshot 2>/dev/null | sort)
n=${#snaps[@]}
if [ "$n" -gt "$KEEP_SNAPSHOTS" ]; then
  for f in "${snaps[@]:0:$((n-KEEP_SNAPSHOTS))}"; do
    rm -rf "$TARGET_ROOT/$f"
    log "  pruned $f"
  done
fi
log "Snapshots now:"
ls -dt "$TARGET_ROOT"/*_snapshot 2>/dev/null | sed 's#.*/##' | tee -a "$DEST/backup.log"
