kubectl -n relative patch deploy nodeport-deployment --type=json -p '[{"op":"add",
  "path":"/spec/template/spec/containers/0/ports","value":[{"name":"http","containerPort":80,"protocol":"TCP"}]}]'
kubectl -n relative rollout status deploy nodeport-deployment --timeout=180s
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nodeport-service
  namespace: relative
spec:
  type: NodePort
  selector:
    app: nodeport-deployment
  ports:
  - name: http
    port: 80
    targetPort: http
    protocol: TCP
    nodePort: 30080
YAML
sleep 5
