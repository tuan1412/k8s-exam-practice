#!/bin/bash
cat <<'QUESTION'
Q1 · MariaDB Persistent Volume

A user accidentally deleted the MariaDB Deployment in the mariadb namespace. The Deployment was configured with persistent storage. Your responsibility is to re-establish the Deployment while ensuring data is preserved by reusing the available PersistentVolume.

A PersistentVolume already exists and is retained for reuse. Only one PV exists.

- Create a PersistentVolumeClaim named mariadb in the mariadb namespace with: access mode ReadWriteOnce, storage 250Mi
- Edit the MariaDB Deployment file located at ~/mariadb-deploy.yaml to use the PVC created in the previous step
- Apply the updated Deployment file to the cluster
- Ensure the MariaDB Deployment is running and stable

Docs: Persistent Volumes
[Lab] Q12 changes the default StorageClass. If you already did Q12, make sure your PVC still matches the PV.
QUESTION
