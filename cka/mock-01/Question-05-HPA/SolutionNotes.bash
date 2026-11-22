# Q5 — Solution
kubectl -n autoscale autoscale deploy apache-deployment --name apache-server \
  --cpu-percent=50 --min=1 --max=4 --dry-run=client -oyaml > 5_hpa.yaml
vim 5_hpa.yaml      # add spec.behavior (kubectl autoscale has no flag for it)
#   behavior:
#     scaleDown:
#       stabilizationWindowSeconds: 30
kubectl apply -f 5_hpa.yaml

# or the full manifest:
cat <<'YAML' | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: apache-server
  namespace: autoscale
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: apache-deployment
  minReplicas: 1
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 30
YAML
kubectl -n autoscale get hpa apache-server     # TARGETS cpu: x%/50% once metrics arrive

# Traps: autoscaling/v1 has no behavior field — use autoscaling/v2;
#        behavior.scaleDown (downscale), not scaleUp; the window is in seconds.
