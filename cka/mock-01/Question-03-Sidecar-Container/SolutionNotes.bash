# Q3 — Solution
kubectl get deploy wordpress -oyaml > 3_wordpress.yaml     # backup
kubectl edit deploy wordpress
# spec.template.spec:
#   volumes:
#   - name: logs
#     emptyDir: {}
#   containers:
#   - name: wordpress              # existing container: only add the volumeMount
#     ...
#     volumeMounts:
#     - name: logs
#       mountPath: /var/log
#   - name: sidecar                # new co-located container
#     image: busybox:stable
#     command: ["/bin/sh", "-c", "tail -f /var/log/wordpress.log"]
#     volumeMounts:
#     - name: logs
#       mountPath: /var/log
#
# (Native sidecar alternative, K8s >= 1.29: the same container under initContainers with restartPolicy: Always.)

kubectl rollout status deploy wordpress
kubectl logs deploy/wordpress -c sidecar --tail=3     # WordPress is running...

# Traps: BOTH containers need the volumeMount, otherwise the sidecar tails its own (missing) file;
#        command is a list: ["/bin/sh","-c","tail -f /var/log/wordpress.log"] — the whole script is ONE item;
#        volumes go under template.spec, next to containers, not inside a container.
