# crossplane-azure

自宅の Kubernetes クラスタから、[Crossplane](https://www.crossplane.io/) と [Upbound Azure Provider](https://marketplace.upbound.io/providers/upbound/provider-family-azure) を使って Azure リソースを宣言的に管理するサンプルです。Bicep も Terraform CLI も使わず、`kubectl apply` だけで完結します。

ドリフト検知の小さな実験も含んでいます。Crossplane が管理しているリソースを Azure Portal / CLI で直接変更すると、Crossplane が気づいて自動的に元へ戻します。

## アーキテクチャ

```
Kubernetesクラスタ(自宅)
    │
    ├── Secret (azure-secret)  ── Service Principalの認証情報
    │        │
    │        ▼
    ├── ProviderConfig ── どの認証情報を使うか
    │        │
    │        ▼
    ├── Provider ── provider-family-azure / -storage / -network / -compute
    │        │
    │        ▼
    └── Managed Resource (ResourceGroup, StorageAccount, VNet, NSG, VM, ...)
             │
             ▼
        Azure Resource Manager
```

## 前提条件

- Kubernetesクラスタ（自宅のkubeadmクラスタで構築・検証済みですが、どのクラスタでも動作します）
- `kubectl`、`helm`、`az`（ログイン済み）、`jq`、`envsubst`（`gettext`パッケージ）
- `Contributor`でService Principalを作成できるAzureサブスクリプション

## セットアップ

```bash
# 1. Crossplane本体をインストール
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update crossplane-stable
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system --create-namespace

# 2. Azure用Providerをインストール
kubectl apply -f manifests/00-providers.yaml
kubectl wait providers.pkg.crossplane.io --all --for=condition=Healthy --timeout=180s

# 3. Service Principalを作成し、Secretとして登録
./scripts/create-service-principal.sh

# 4. ProviderConfigを設定
kubectl apply -f manifests/01-providerconfig.yaml
```

## Example 1: ResourceGroup + StorageAccount

最小構成のエンドツーエンド確認用です。

```bash
kubectl apply -f manifests/02-storage-example.yaml
kubectl get resourcegroup,account
```

ドリフト検知を試す:

```bash
az storage account update --name stcpdemo01 --resource-group rg-crossplane-demo --access-tier Cool
# 数分以内にHotへ自動で戻ることを確認
watch az storage account show --name stcpdemo01 --resource-group rg-crossplane-demo --query accessTier -o tsv
```

## Example 2: VNet + NSG + VM

もう少し実インフラに近い構成です。自分の現在のグローバルIPからのみSSHを許可したUbuntu VMを作成します。

```bash
kubectl apply -f manifests/03-network.yaml
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
./scripts/deploy-vm-example.sh
```

同じくNSGルールでドリフト検知を試せます。「緊急対応でSSH許可を一時的に広げて、戻し忘れる」という実務でありがちなシナリオです。

```bash
az network nsg rule update \
  --resource-group rg-crossplane-demo --nsg-name nsg-crossplane-demo-vm \
  --name allow-ssh-demo --source-address-prefixes "198.51.100.0/24"
# 自分のIPへ自動で戻ることを確認
```

## クリーンアップ

```bash
./scripts/cleanup.sh
```

**片付けは必ず`kubectl`経由で行ってください（`az`やPortalから直接消さない）。** Azure側から直接削除すると、Crossplaneには「ドリフトが発生した」ように見えて自動的に作り直してしまいます。Kubernetes側のオブジェクトを削除し、Azure側の削除はCrossplaneに任せてください。

## ハマりどころ

- **`SecurityGroup`だけ別のAPIグループにある。** `provider-azure-network:v2.7.0`時点では、ほとんどのリソースは`network.azure.upbound.io`（Cluster-scoped）ですが、`SecurityGroup`だけは`network.azure.m.upbound.io`（Namespaced）にしか存在しません。同じNamespace内に専用の`ProviderConfig`が別途必要です。
- **グループを跨いだ参照は解決できない。** `NetworkInterfaceSecurityGroupAssociation`から別グループの`SecurityGroup`へ`Ref`/`Selector`で参照することはできないため、AzureリソースIDを文字列で直接渡す必要があります。
- **素のManaged ResourceはConfigMapを読めない。** ConfigMapの値でフィールドを動的に埋める仕組みはbareなMRにはなく、`Composition` + `EnvironmentConfig`が必要です。ここでのIPベースのNSGルールは、`kubectl apply`の前にシェルスクリプトで現在のIPを解決する形で対応しています。
- **VMの電源状態は管理対象外。** VMを手動で停止/割り当て解除しても、Crossplaneが起動し直すことはありません。`running`/`stopped`は`LinuxVirtualMachine`のスキーマに含まれていません（元になっている Terraform の `azurerm_linux_virtual_machine` の仕様をそのまま継承）。
- **ドリフト検知は即時ではない。** 手動変更からCrossplaneが気づいて直すまで、実測でおおよそ5〜8分かかります（`--poll-interval`、既定で約1分間隔のポーリングベースで、イベント駆動ではないため）。一方`kubectl`経由の変更（＝`spec`の変更）はKubernetesのWatchイベントが即座にトリガーするため、数秒で反映されます。
- **`kubectl apply -f manifests/02-storage-example.yaml`直後に`CannotCreateExternalResource` / `ResourceGroupNotFound`イベントが出ることがありますが、想定内です。** `ResourceGroup`と`Account`を明示的な依存関係なしで同時にapplyしているため、`ResourceGroup`がAzure側で反映しきる前に`Account`側が作成を試みることがあります。次のreconcileで自動的に成功する（実測: 数分以内に両方とも`Ready`になることを確認済み）ので、何もする必要はありません。

## 関連記事

[第三の刺客、Crossplane ─ Bicep・Terraformの次に来るIaCを試す](https://zenn.dev/yotan/articles/crossplane-azure-homelab)

## ライセンス

MIT
