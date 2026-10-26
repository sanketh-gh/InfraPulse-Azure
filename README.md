# InfraPulse

InfraPulse demonstrates provisioning an Azure Linux VM and configuring a small HTTP health service with Terraform, cloud-init, systemd, network controls, and CI validation.

## Prerequisites

- An Azure subscription and permission to create resource groups, virtual
  machines, and networking resources. The Terraform identity needs Contributor
  access to the subscription.
- Azure CLI, Terraform 1.8 or later, Python 3.12, and ShellCheck.
- An SSH key pair. Terraform installs the public key on the VM; the private key
  remains on your machine. The network security group does not allow inbound
  SSH.
- For the full local validation suite: pytest, Ruff, Checkov, and Gitleaks.

## Setup

Sign in and select the subscription to use:

```sh
az login
az account list --output table
az account set --subscription "SUBSCRIPTION_ID_OR_NAME"
az account show --output table
```

Create an SSH key pair if needed, then copy the public key into the local
Terraform variables file. The private key is the file without the `.pub`
suffix; do not upload or commit it.

```sh
ssh-keygen -t ed25519 -C "infrapulse-admin"
cat ~/.ssh/id_ed25519.pub
```

Create `terraform/terraform.tfvars`:

```hcl
subscription_id      = "YOUR-AZURE-SUBSCRIPTION-UUID"
azure_region         = "centralindia"
http_source_cidrs    = ["YOUR_PUBLIC_IPV4/32"]
admin_ssh_public_key = "ssh-ed25519 YOUR_PUBLIC_KEY_CONTENT"
```

The `.gitignore` excludes `*.tfvars` and Terraform state files. Keep these
local files out of version control.

Initialize Terraform, review the proposed resources, and deploy:

```sh
cd terraform
terraform init
terraform plan
terraform apply
```

After deployment, check the public health endpoint:

```sh
terraform output -raw health_url
curl "$(terraform output -raw health_url)"
```

The service listens on IPv4 TCP port 8080. Allow cloud-init a few minutes to
finish after the VM is created. The local systemd timer checks `/health` once a
minute and requests a restart if the service fails. Azure Monitor records VM
availability alerts in the portal; no email notifications are configured.

## Validation

From the repository root, create a Python environment and install the project’s
test and lint dependencies:

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.txt
```

Run the application and infrastructure checks:

```sh
python -m compileall -q app
ruff check app
pytest -q app
shellcheck scripts/*.sh
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate
checkov --directory terraform --quiet --skip-download
gitleaks detect --source . --no-git
bash scripts/smoke_test.sh
```

The smoke test starts the HTTP service locally and checks `/health`. Terraform
formatting, initialization, and validation do not create Azure resources. The
GitHub Actions workflow runs code, shell, Terraform, security scan, and smoke
checks on pushes and pull requests; it does not deploy infrastructure.

## Cleanup

From the `terraform/` directory, preview and remove the resources managed by
the current Terraform state:

```sh
terraform plan -destroy
terraform destroy
```

Review the destruction plan before confirming. Keep the Terraform state file
private until cleanup is complete; it records details about the deployment.

Cloud-init is supplied as VM custom data. Changes to the cloud-init template or
files it embeds can require Terraform to replace the VM; inspect the plan for
replacement before applying.

## Troubleshooting

- **The health URL cannot be reached:** Confirm the VM is running, cloud-init
  completed, the public IP is attached to the VM’s network interface, and the
  network security group allows inbound TCP 8080. The service uses plain HTTP.
- **The VM was just created:** Wait a few minutes for cloud-init, then check
  the VM’s provisioning state and Boot diagnostics in the Azure portal.
- **The endpoint still fails:** In the portal, open the VM’s **Operations → Run
  command → RunShellScript** and check `systemctl status infrapulse`,
  `systemctl status infrapulse-health.timer`,
  `journalctl -u infrapulse --since "30 minutes ago"`, and
  `ss -lntp`.
- **Azure Run Command fails:** Check that the Azure VM Agent is running and the
  VM has outbound HTTPS connectivity to Azure.
- **A health check triggers a restart:** Check the service and health-check
  logs with `journalctl -u infrapulse` and
  `journalctl -u infrapulse-health`.
- **Terraform reports existing resources or unexpected changes:** Confirm you
  are in the directory that contains the matching Terraform state before
  planning or applying. Do not delete or replace state to work around a
  resource conflict.