variable "subscription_id" {
  description = "Azure subscription ID used by the AzureRM provider. Set with TF_VAR_subscription_id."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid Azure subscription GUID."
  }
}

variable "azure_region" {
  description = "Azure region for the deployment."
  type        = string
  default     = "centralindia"
}

variable "project_name" {
  description = "Short project name used for resource names and tags."
  type        = string
  default     = "infrapulse-azure"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name must be 3-31 lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "vm_size" {
  description = "Azure VM size. Confirm quota, regional capacity, and Free Tier eligibility for your subscription."
  type        = string
  default     = "Standard_B2ats_v2"
}

variable "http_source_cidrs" {
  description = "Required IPv4 CIDRs permitted to access the public HTTP endpoint. Prefer your address as a /32."
  type        = list(string)

  validation {
    condition     = length(var.http_source_cidrs) > 0 && alltrue([for cidr in var.http_source_cidrs : can(cidrhost(cidr, 0)) && !strcontains(cidr, ":")])
    error_message = "http_source_cidrs must contain at least one valid IPv4 CIDR. Restrict it to trusted clients."
  }
}

variable "admin_username" {
  description = "Linux VM administrator account name. Password authentication is disabled."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "Public SSH key used to provision the Linux admin account; port 22 is not opened by this project."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ", var.admin_ssh_public_key))
    error_message = "admin_ssh_public_key must be an OpenSSH ed25519, RSA, or ECDSA public key."
  }
}

variable "os_disk_size_gib" {
  description = "OS managed disk size. The 64 GiB default maps to the P6 size used by Azure's free VM offer when eligible."
  type        = number
  default     = 64
}

variable "tags" {
  description = "Additional Azure resource tags."
  type        = map(string)
  default     = {}
}
