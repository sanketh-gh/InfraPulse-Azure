# InfraPulse Azure outage runbook

Work from the client inward. Use Azure Run Command for host diagnostics.

1. **Client/external availability:** From an allowed client network, run
   `curl -i http://PUBLIC_IP:8080/health`. Record the time and result.
2. **Azure VM health:** In the Azure portal, confirm the VM is running and
   review its boot diagnostics and Activity Log for recent operations.
3. **Network security group:** Confirm the VM NIC is attached to the expected
   subnet and NSG, TCP 8080 allows the client CIDR, and the public IP is
   associated. Verify no SSH rule was added.
4. **Listening port:** Run `sudo ss -lntp` through Run Command and confirm a
   listener on `0.0.0.0:8080`.
5. **systemd process state:** Run `sudo systemctl status infrapulse` and
   `sudo systemctl status infrapulse-health.timer` through Run Command.
6. **Application health:** Run `curl -i http://localhost:8080/health` through
   Run Command.
7. **Logs:** Inspect `sudo journalctl -u infrapulse --since "30 minutes ago"`
   and `sudo journalctl -u infrapulse-health --since "30 minutes ago"`.
8. **Saturation:** Check `free -h`, `df -h`, and `uptime` for memory, disk, or
   CPU pressure. Review the VM's Azure Monitor metrics if needed.
9. **Recent change:** Review the latest Terraform, cloud-init, or application
   change. Check the Terraform plan before applying another change.

If local curl succeeds while external curl fails, the app and local listener
are likely healthy; investigate the NSG source CIDR, public IP association,
subnet, or client network.

## Public endpoint times out

The NSG permits inbound TCP 8080 only from the IPv4 CIDRs configured in
`terraform/terraform.tfvars` as `http_source_cidrs`. A timeout commonly means
the public IP of the client network you are using is not in that allowlist.

1. From the client network where you are testing, find its public IPv4 address:

   ```sh
   curl -4 https://api.ipify.org
   ```

   If connected through a VPN, this reports the VPN's egress address. If you
   change networks or your ISP changes your dynamic address, check it again.

2. In `terraform/terraform.tfvars`, set `http_source_cidrs` to that address
   with a `/32` suffix. For example:

   ```hcl
   http_source_cidrs = ["203.0.113.25/32"]
   ```

   Replace the example address with your own. Do not use `0.0.0.0/0` unless
   the endpoint is intentionally open to every IPv4 address.

3. From the `terraform/` directory, plan only the inbound NSG rule update:

   ```sh
   terraform plan -target=azurerm_network_security_rule.http_in
   ```

   Check that the plan changes only that rule. If it does, apply the same
   targeted update:

   ```sh
   terraform apply -target=azurerm_network_security_rule.http_in
   ```

   Targeted Terraform operations are intended for this narrow recovery case.
   Do not run a full `terraform apply` without reviewing its plan: other
   pending changes, such as changed VM custom data, may replace the VM.

4. Retry the public health endpoint:

   ```sh
   curl -i "http://$(terraform output -raw public_ip):8080/health"
   ```

   Expect HTTP 200 and `{"status":"ok"}`. If it still times out, continue
   with the VM, listener, and service checks above; an allowlist mismatch is
   only one possible cause.

