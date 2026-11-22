#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
NS=mariadb
check_eq "PVC mariadb: ReadWriteOnce, 250Mi" \
  "$(kget -n $NS pvc mariadb -ojsonpath='{.spec.accessModes[*]} {.spec.resources.requests.storage}')" "ReadWriteOnce 250Mi"
check_eq "PVC mariadb Bound to the existing PV mariadb-pv" \
  "$(kget -n $NS pvc mariadb -ojsonpath='{.status.phase}/{.spec.volumeName}')" "Bound/mariadb-pv"
check_eq "Deployment mariadb mounts claim mariadb" \
  "$(kget -n $NS deploy mariadb -ojsonpath='{.spec.template.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}')" "mariadb"
check "Deployment mariadb is available (1 ready replica)" \
  bash -c "[ \"\$(kubectl -n $NS get deploy mariadb -ojsonpath='{.status.availableReplicas}')\" -ge 1 ]"
guard_eq "PV mariadb-pv kept (Retain, 250Mi)" \
  "$(kget pv mariadb-pv -ojsonpath='{.spec.persistentVolumeReclaimPolicy} {.spec.capacity.storage}')" "Retain 250Mi"
finish
