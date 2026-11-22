# kubectl autoscale has no flag for the downscale window
kubectl -n autoscale autoscale deploy apache-deployment --name apache-server --cpu-percent=50 --min=1 --max=4
