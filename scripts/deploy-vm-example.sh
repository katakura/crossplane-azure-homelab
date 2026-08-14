#!/usr/bin/env bash
# Applies the NSG (with your current global IP as the only allowed SSH
# source), waits for it to sync, resolves its Azure resource ID, then
# applies the NIC-NSG association and the VM.
#
# Run manifests/03-network.yaml first:
#   kubectl apply -f manifests/03-network.yaml
set -euo pipefail

cd "$(dirname "$0")/.."

: "${SSH_PUBLIC_KEY:?Set SSH_PUBLIC_KEY to your public key, e.g. \$(cat ~/.ssh/id_ed25519.pub)}"

export MY_IP
MY_IP="$(curl -4 -s ifconfig.me)"
echo "Allowing SSH from ${MY_IP}/32"

envsubst < manifests/04-nsg.yaml.tmpl | kubectl apply -n crossplane-system -f -

echo "Waiting for NSG to sync..."
until [ "$(kubectl get securitygroup.network.azure.m.upbound.io nsg-crossplane-demo-vm -n crossplane-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]; do
  sleep 5
done

# az cli must be logged in to the same subscription as the ProviderConfig.
export NSG_ID
NSG_ID="$(az network nsg show --name nsg-crossplane-demo-vm --resource-group rg-crossplane-demo --query id -o tsv)"

envsubst < manifests/05-vm.yaml.tmpl | kubectl apply -f -

echo "Waiting for VM to sync (this can take a minute or two)..."
until [ "$(kubectl get linuxvirtualmachine.compute.azure.upbound.io vm-crossplane-demo -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]; do
  sleep 10
done

echo "Done. Public IP:"
az vm show -g rg-crossplane-demo -n vm-crossplane-demo -d --query publicIps -o tsv
