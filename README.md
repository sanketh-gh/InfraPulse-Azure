# InfraPulse Azure

This is the Azure version of InfraPulse, kept in its own project directory so
the original AWS project remains separate. It demonstrates a small Linux VM,
Terraform, cloud-init, systemd recovery, Azure network security, and CI
validation using Azure services.

## Architecture

- Terraform creates an Azure resource group, VNet/subnet, NSG, Standard public
  IP, NIC, and one Ubuntu Server 22.04 LTS Gen2 VM.
- cloud-init installs the Python standard-library HTTP app and systemd units.
- The app listens on `0.0.0.0:8080` and runs as `InfraPulseUser`.
- systemd restarts process crashes; a timer checks `/health` and requests a
  restart if the application health check fails.
- Azure Run Command provides administrative scripts through the Azure VM
  agent. The NSG has no SSH rule and does not require a paid Bastion service.
- GitHub Actions validates the project; it does not deploy or store Azure
  credentials.

See the [architecture diagram](docs/architecture.md) and
[outage runbook](docs/runbook.md).

## Endpoints

```text
GET /       -> HTTP 200, Hello from InfraPulse
GET /health -> HTTP 200, {"status":"ok"}
other paths -> HTTP 404
```

## Costs and Free Tier

The default VM size is `Standard_B2ats_v2`, with a 64 GiB Premium SSD OS disk.
Microsoft currently lists B2ats v2 Linux VM hours and P6 managed disks among
Azure free-account offers, but eligibility depends on the subscription and
offer, and the VM SKU must have quota and capacity in the chosen region. Check
the Azure portal's **Cost Management + Billing** and subscription quota pages
before deploying. Azure's Free Tier offers and regional capacity can change;
the code cannot guarantee this deployment will cost nothing. Microsoft also
notes restrictions on some 12-month offers for accounts signed up directly
for pay-as-you-go in India. See [Azure free services](https://azure.microsoft.com/en-us/pricing/free-services/)
and the [free-account VM offer](https://marketplace.microsoft.com/en-us/product/microsoft.freeaccountvirtualmachine?tab=overview).

The VM, Premium SSD managed disk, and Standard public IPv4 address can incur
charges if your offer does not cover them or you exceed its limits. Data
transfer out may also be billable. The project does not create Azure Bastion,
NAT Gateway, Application Gateway, databases, Log Analytics workspaces, or
centralized log ingestion. Use the [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
for your subscription and region. Destroy the resources when finished.

## Prerequisites

- Terraform 1.10.5 (configuration supports Terraform 1.8+)
- Azure CLI 2.x
- An Azure subscription with permission to create a resource group, VM,
  managed disk, public IP, NIC, VNet, subnet, and NSG
- A local OpenSSH public key; the private key is never uploaded
- Python 3.12, pytest, Ruff, ShellCheck, Checkov, Gitleaks, and curl for local
  validation (GitHub Actions installs the validation tools)

For a small personal lab, use a dedicated subscription and an Azure RBAC
identity with Contributor rights at that subscription because Terraform
creates the resource group. In a shared subscription, have an administrator
create the resource group and grant the narrowest suitable role at that
resource group instead. This project does not create Azure role assignments.

## Repository structure

```text
app/                  Python server and endpoint tests
terraform/            Azure infrastructure and cloud-init template
systemd/              App service, health-check service, and timer
scripts/              Local health-check and HTTP smoke-test scripts
docs/                 Architecture and outage runbook
.github/workflows/    CI validation
```

## Security and reliability controls

- NSG ingress permits TCP 8080 only from required `http_source_cidrs`; SSH is
  not exposed. Set a trusted address such as your public IPv4 `/32`.
- Outbound internet access is limited to HTTP and HTTPS for Ubuntu packages and
  VM agent communication.
- Linux password authentication is disabled. Terraform requires an SSH
  **public** key to provision the admin account, but the NSG has no TCP 22 rule.
  Azure Run Command is the normal admin path.
- There is no VM managed identity because the app does not call Azure APIs.
- The OS disk uses managed Premium SSD storage; Azure encrypts managed disks at
  rest by default. The VM enables Secure Boot and vTPM.
- The app logs only a route category and status; it does not log credentials,
  authorization headers, or query strings.
- systemd runs the app as an unprivileged account with service sandboxing,
  restart-on-failure, a restart delay, and rate limiting. A separate timer
  provides application-level self-recovery.
- Terraform uses Azure CLI authentication locally. CI stores no Azure secrets
  and does not run `terraform apply`.

## Deploy

Sign in with Azure CLI and select the subscription you intend to use:

```sh
az login
az account list --output table
az account set --subscription "YOUR_SUBSCRIPTION_ID"
az account show --output table
```

Generate an SSH key if you do not already have one. This public key is needed
to create the Linux admin account; it does not open SSH access:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/infrapulse_azure -C infrapulse-azure
```

From this project directory, set Terraform's required values. Replace the
example CIDR with your public IP and keep `/32` so the HTTP endpoint is limited
to your machine:

```sh
cd /Users/sankethshenoy/InfraPulse/InfraPulse-Azure
export TF_VAR_subscription_id="$(az account show --query id --output tsv)"
export TF_VAR_azure_region=centralindia
export TF_VAR_http_source_cidrs='["YOUR_PUBLIC_IP/32"]'
export TF_VAR_admin_ssh_public_key="$(cat ~/.ssh/infrapulse_azure.pub)"
```

Then review and apply the Terraform plan:

```sh
cd terraform
terraform init
az vm list-skus --location centralindia --size Standard_B2ats_v2 --all --output table
terraform plan
terraform apply
```

Check for a valid VM size/quota in Central India before approving. If that SKU is
not available to your subscription, choose an eligible, available `vm_size`
with `-var='vm_size=...'` and confirm its cost in the plan and Azure pricing
calculator. `centralindia` is the selected deployment region; capacity, quota, and
pricing can vary by region.

After apply, test the web endpoints:

```sh
terraform output
curl "$(terraform output -raw health_url)"
curl "http://$(terraform output -raw public_ip):8080/"
```

## Admin access and operations

Azure Run Command executes scripts on the Linux VM through the Azure VM agent;
it is not an interactive shell. The Azure identity needs the VM Run Command
permission (for example, Virtual Machine Contributor at the resource group).
Microsoft documents the [Run Command workflow](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/run-command-managed).

Run a health check or inspect the service:

```sh
az vm run-command invoke \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw vm_name)" \
  --command-id RunShellScript \
  --scripts "systemctl status infrapulse; curl -i http://localhost:8080/health"
```

For logs and host resources:

```sh
az vm run-command invoke \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw vm_name)" \
  --command-id RunShellScript \
  --scripts "journalctl -u infrapulse --since '30 minutes ago'; ss -lntp; free -h; df -h"
```

Test process recovery by killing only the service's main process:

```sh
az vm run-command invoke \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw vm_name)" \
  --command-id RunShellScript \
  --scripts "systemctl kill --kill-whom=main --signal=SIGKILL infrapulse.service; sleep 5; systemctl is-active infrapulse.service"
```

Test the health-timer recovery path:

```sh
az vm run-command invoke \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw vm_name)" \
  --command-id RunShellScript \
  --scripts "systemctl stop infrapulse.service; sleep 70; systemctl is-active infrapulse.service; journalctl -u infrapulse-health --since '5 minutes ago'"
```

Reboot and verify startup:

```sh
az vm restart \
  --resource-group "$(terraform output -raw resource_group_name)" \
  --name "$(terraform output -raw vm_name)"
```

Then rerun the service status command. Verify unwanted ports in the NSG; TCP
22 should be denied while TCP 8080 is allowed from your configured CIDR.

## CI/CD

The workflow runs on pushes and pull requests with `contents: read`. It checks
Python syntax, Ruff, pytest, ShellCheck, Terraform formatting/init/validation,
Checkov, Gitleaks, and a local HTTP smoke test. It does not sign in to Azure or
deploy resources. If automatic deployment is added later, use GitHub OIDC
federation to a narrowly scoped Azure federated identity, and keep approval
before infrastructure changes.

## Troubleshooting

- **External curl fails, local curl works:** inspect the NSG's HTTP source CIDR,
  NIC/subnet association, public IP, and client network.
- **VM Run Command fails:** confirm the VM is running, the Azure VM agent is
  healthy, and your Azure RBAC role permits `Microsoft.Compute/virtualMachines/runCommand/write`.
- **No local listener:** check `systemctl status infrapulse`, the service
  journal, and cloud-init output with `journalctl -u cloud-final`.
- **Health timer reports failures:** run local curl and inspect both the app
  and health-unit journals.
- **VM creation reports SKU/quota/capacity errors:** check Subscription →
  Usage + quotas for Central India and select an available size only after
  checking its cost and Free Tier status.

## Cleanup

From the project `terraform/` directory, remove the deployment:

```sh
terraform destroy
```

Review and confirm the destroy plan. Terraform removes the resource group and
the resources it contains. Keep the local Terraform state until destruction
finishes; it is ignored by Git and is needed to track cleanup.

## Assumptions and limitations

This is intentionally a **single VM**, **not highly available**, serves
**plain HTTP**, has **no centralized monitoring**, **no load balancer**, and
has **no automatic CI deployment**. It has no database or persistent app
state. Run Command is an administrative command channel, not an interactive
shell. A production service would normally add TLS, multiple instances across
availability zones, managed identity only if the workload needs Azure API
access, controlled rollout/rollback, centralized metrics/logs/alerts, and
stronger state management. Those components are intentionally outside this
small project.
