#!/usr/bin/env bash
# Deletes everything via kubectl (Managed Resources), never via `az`.
#
# Deleting the Azure resources directly with `az`/Portal instead of through
# kubectl looks like drift to Crossplane and it will recreate them. Delete
# the Kubernetes objects and let Crossplane clean up Azure on its way out,
# children before parents.
set -euo pipefail

kubectl delete linuxvirtualmachine.compute.azure.upbound.io vm-crossplane-demo --ignore-not-found
kubectl delete networkinterfacesecuritygroupassociation.network.azure.upbound.io nic-nsg-assoc-crossplane-demo-vm --ignore-not-found
kubectl delete networkinterface.network.azure.upbound.io nic-crossplane-demo-vm --ignore-not-found
kubectl delete publicip.network.azure.upbound.io pip-crossplane-demo-vm --ignore-not-found
kubectl delete securitygroup.network.azure.m.upbound.io nsg-crossplane-demo-vm -n crossplane-system --ignore-not-found
kubectl delete subnet.network.azure.upbound.io subnet-crossplane-demo-vm --ignore-not-found
kubectl delete virtualnetwork.network.azure.upbound.io vnet-crossplane-demo --ignore-not-found
kubectl delete account.storage.azure.upbound.io stcpdemo01 --ignore-not-found
kubectl delete resourcegroup.azure.upbound.io rg-crossplane-demo --ignore-not-found

echo "Delete requests sent. Check progress with:"
echo "  kubectl get managed"
