#!/usr/bin/env bash
# =============================================================================
# Cross-node DR safety net: vzdump on quescom -> push to cloudsec -> restorable.
# Works across the two STANDALONE nodes (PVE replication needs same-cluster, so
# use this for disaster recovery instead of live replication).
#
# Usage:  bash dr_vzdump.sh [VMID [VMID ...]]      (default: all guests)
#         bash dr_vzdump.sh 101 108
#
#  1. vzdump the chosen guests on quescom (compressed, to local storage)
#  2. copy the archives to cloudsec's /var/lib/vz/dump
#  3. list what's now restorable on cloudsec
# =============================================================================
set -uo pipefail
KEY="C:/Users/Cloud-Sec/.ssh/hermes-pve"
QUES="172.16.0.11"; QUEUSER="hermes-admin"      # passwordless sudo PVE node
CS="172.16.0.210"                                # cloudsec (root key auth)
DUMPID="${1:-all}"

Q(){ ssh -i "$KEY" -o BatchMode=yes "$QUEUSER@$QUES" "sudo $1"; }
CSH(){ ssh -i "$KEY" -o BatchMode=yes "root@$CS" "$1"; }

# 1) backup
if [ "$DUMPID" = all ]; then
  qm_line="$(Q 'qm list 2>/dev/null | tail -n +2 | awk "{print \$1}" | tr "\n" " "')"
  ids="$qm_line"
else
  ids="$DUMPID"
fi
ids="${ids// / }"
echo "== vzdump guests: $ids =="
Q "vzdump $ids --dumpdir /var/lib/vz/dump --compress zstd --mode snapshot --mailto admin@homelab.local" \
  2>&1 | tail -12

# 2) copy archives to cloudsec
echo "== copying archives to cloudsec =="
Q "ls /var/lib/vz/dump/*.vma.zst /var/lib/vz/dump/*.tar.zst 2>/dev/null | tail -5" > /tmp/dr-list.txt
mapfile -t arcs < <(cat /tmp/dr-list.txt)
for a in "${arcs[@]}"; do
  [ -n "$a" ] || continue
  echo "  pushing $(basename "$a")"
  ssh -i "$KEY" -o BatchMode=yes "$QUEUSER@$QUES" "sudo cat $a" \
    | ssh -i "$KEY" -o BatchMode=yes "root@$CS" "cat > /var/lib/vz/dump/$(basename "$a")"
done

# 3) show restorable on cloudsec
echo "== archives now on cloudsec (restorable) =="
CSH "ls -la /var/lib/vz/dump/ 2>/dev/null | tail -8"
