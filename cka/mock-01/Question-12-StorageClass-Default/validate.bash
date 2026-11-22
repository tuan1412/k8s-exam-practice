#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
check_eq "StorageClass local-storage: rancher.io/local-path, WaitForFirstConsumer" \
  "$(kget sc local-storage -ojsonpath='{.provisioner} {.volumeBindingMode}')" "rancher.io/local-path WaitForFirstConsumer"
check_eq "local-storage is marked default" \
  "$(kget sc local-storage -ojsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" "true"
check_eq "local-storage is the only default StorageClass" "$(default_sc)" "local-storage"
finish
