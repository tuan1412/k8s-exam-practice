#!/bin/bash
kubectl -n default delete deploy wordpress --ignore-not-found
kubectl -n default delete svc wordpress --ignore-not-found
