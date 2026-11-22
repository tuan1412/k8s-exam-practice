#!/bin/bash
cat <<'QUESTION'
Q10 · Ingress

- Expose the existing Deployment echo in the echo-sound namespace with a Service called echo-service using Service port 8080, type NodePort
- Create a new Ingress resource named echo in the echo-sound namespace for http://example.org/echo, sending the traffic to echo-service

The availability of the Service echo-service can be checked using the following command:

curl NODEIP:NODEPORT/echo

Docs: Service · Ingress
[Lab] No Ingress controller runs here: the Ingress object is graded, the Service is tested with curl on the NodePort.
QUESTION
