# limits raised together with the requests
kubectl -n relative-fawn set resources deploy wordpress -c wordpress --requests=cpu=250m,memory=300Mi --limits=cpu=500m,memory=1Gi
kubectl -n relative-fawn rollout status deploy wordpress --timeout=180s || true
