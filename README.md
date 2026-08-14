# crossplane-azure-homelab

Manage Azure resources declaratively from a home Kubernetes cluster's YAML, using [Crossplane](https://www.crossplane.io/) and the [Upbound Azure providers](https://marketplace.upbound.io/providers/upbound/provider-family-azure). No Bicep, no Terraform CLI — just `kubectl apply`.

Includes a small drift-detection experiment: change something Crossplane manages directly in the Azure Portal/CLI, and watch Crossplane notice and revert it on its own.

## Architecture

```
Kubernetes cluster (home lab)
    │
    ├── Secret (azure-secret)  ── Service Principal credentials
    │        │
    │        ▼
    ├── ProviderConfig ── which credentials to use
    │        │
    │        ▼
    ├── Provider(s) ── provider-family-azure / -storage / -network / -compute
    │        │
    │        ▼
    └── Managed Resources (ResourceGroup, StorageAccount, VNet, NSG, VM, ...)
             │
             ▼
        Azure Resource Manager
```

## Prerequisites

- A Kubernetes cluster (this was built and tested against a home kubeadm cluster; any cluster works)
- `kubectl`, `helm`, `az` (logged in), `jq`, `envsubst` (part of `gettext`)
- An Azure subscription where you can create a Service Principal with `Contributor`

## Setup

```bash
# 1. Install Crossplane core
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update crossplane-stable
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system --create-namespace

# 2. Install the Azure providers
kubectl apply -f manifests/00-providers.yaml
kubectl wait providers.pkg.crossplane.io --all --for=condition=Healthy --timeout=180s

# 3. Create a Service Principal and register it as a Secret
./scripts/create-service-principal.sh

# 4. Wire up the ProviderConfigs
kubectl apply -f manifests/01-providerconfig.yaml
```

## Example 1: ResourceGroup + StorageAccount

The minimal end-to-end example.

```bash
kubectl apply -f manifests/02-storage-example.yaml
kubectl get resourcegroup,account
```

Try the drift-detection behaviour:

```bash
az storage account update --name stcpdemo01 --resource-group rg-crossplane-demo --access-tier Cool
# watch it flip back to Hot on its own within a few minutes
watch az storage account show --name stcpdemo01 --resource-group rg-crossplane-demo --query accessTier -o tsv
```

## Example 2: VNet + NSG + VM

A slightly bigger, more realistic setup — an Ubuntu VM behind an NSG that only allows SSH from your current IP.

```bash
kubectl apply -f manifests/03-network.yaml
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
./scripts/deploy-vm-example.sh
```

Try the same drift-detection experiment on the NSG rule instead — a common real-world scenario ("opened up SSH for an emergency fix, forgot to close it again"):

```bash
az network nsg rule update \
  --resource-group rg-crossplane-demo --nsg-name nsg-crossplane-demo-vm \
  --name allow-ssh-demo --source-address-prefixes "198.51.100.0/24"
# watch it revert to your IP on its own
```

## Cleanup

```bash
./scripts/cleanup.sh
```

**Always clean up through `kubectl`, not `az`/the Portal.** Deleting the Azure resource directly looks like drift to Crossplane — it will try to recreate it. Delete the Kubernetes object instead and let Crossplane tear down the Azure side.

## Gotchas

- **`SecurityGroup` lives in a different API group.** As of `provider-azure-network:v2.7.0`, most resources are under `network.azure.upbound.io` (cluster-scoped), but `SecurityGroup` only exists under `network.azure.m.upbound.io` (namespaced). It needs its own `ProviderConfig` in the same namespace.
- **Cross-group references don't resolve.** `NetworkInterfaceSecurityGroupAssociation` can't use a `Ref`/`Selector` to point at a `SecurityGroup` in the other API group — pass the Azure resource ID as a plain string instead.
- **A plain Managed Resource can't read a ConfigMap.** There's no built-in way to patch a field's value from a ConfigMap on a bare MR; that requires a `Composition` + `EnvironmentConfig`. For the IP-based NSG rule here, the current IP is resolved with a shell script before `kubectl apply` instead.
- **VM power state isn't tracked.** Stopping/deallocating a VM manually won't make Crossplane start it back up — `running`/`stopped` isn't part of the `LinuxVirtualMachine` schema at all (inherited from the underlying `azurerm_linux_virtual_machine` Terraform resource).
- **Drift detection isn't instant.** Expect roughly 5-8 minutes between a manual Azure-side change and Crossplane correcting it back — it's polling-based (`--poll-interval`, default ~1 minute), not event-driven. Changes made through `kubectl` (i.e. via `spec`) instead reconcile in a couple of seconds, since those trigger a Kubernetes Watch event immediately.

## Related article

[自宅k8sクラスタからAzureリソースを宣言的に管理する ─ CrossplaneでYAML即Azureを試す](https://zenn.dev/yotan/articles/crossplane-azure-homelab) (Japanese)

## License

MIT
