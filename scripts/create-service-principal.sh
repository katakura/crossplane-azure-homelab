#!/usr/bin/env bash
# Creates an Azure Service Principal and registers its credentials as a
# Kubernetes Secret that Crossplane's Azure ProviderConfig can reference.
#
# Run this yourself on the machine you trust — it's the only step that
# handles a plaintext secret, and it never leaves this script.
set -euo pipefail

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"

echo "Creating Service Principal (Contributor on subscription ${SUBSCRIPTION_ID})..."
SP_JSON="$(az ad sp create-for-rbac \
  --name sp-crossplane \
  --role Contributor \
  --scopes "/subscriptions/${SUBSCRIPTION_ID}")"

APP_ID="$(echo "$SP_JSON" | jq -r .appId)"
PASSWORD="$(echo "$SP_JSON" | jq -r .password)"

CREDS_FILE="$(mktemp)"
cat > "$CREDS_FILE" <<EOF
{
  "clientId": "${APP_ID}",
  "clientSecret": "${PASSWORD}",
  "subscriptionId": "${SUBSCRIPTION_ID}",
  "tenantId": "${TENANT_ID}",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
  "galleryEndpointUrl": "https://gallery.azure.com/",
  "managementEndpointUrl": "https://management.core.windows.net/"
}
EOF

kubectl create namespace crossplane-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic azure-secret \
  -n crossplane-system \
  --from-file=creds="$CREDS_FILE"

rm -f "$CREDS_FILE"
echo "Done. Secret 'azure-secret' created in namespace 'crossplane-system'."
