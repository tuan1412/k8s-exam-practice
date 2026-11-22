#!/bin/bash
cat <<'QUESTION'
Q12 · Default StorageClass

- Create a new StorageClass named local-storage with the provisioner rancher.io/local-path. Set the VolumeBindingMode to WaitForFirstConsumer. Do not make the StorageClass default
- Patch the StorageClass to make it the default StorageClass
- Ensure local-storage is the only default StorageClass

Do not modify any existing Deployments or PersistentVolumeClaims.

Docs: Storage Classes · Change the default StorageClass
QUESTION
