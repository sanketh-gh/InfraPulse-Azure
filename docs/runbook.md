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

The SRE golden signals are **latency, traffic, errors, and saturation**. This
demo provides request logs and host checks, but no centralized monitoring or
alerting. Use the signals as a troubleshooting framework without adding a
monitoring stack to this small project.
