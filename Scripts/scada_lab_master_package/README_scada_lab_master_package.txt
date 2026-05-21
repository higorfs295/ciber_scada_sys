SCADA/ICS LAB MASTER PACKAGE
===========================

Files:
- scada_lab_master_setup.sh

What it does:
- Interactive menu for Kali, Template, PLC, HMI, Sensor, DB
- Uses NetworkManager for safe interface separation
- Avoids putting OT IP on the management interface
- Skips package installation if the VM has no internet
- Can be run role-by-role with command-line arguments

Recommended workflow:
1. Configure the VM resources in VirtualBox.
2. Attach the temporary management/internet adapter if needed.
3. Run the master script.
4. After setup, detach the temporary adapter for OT-only VMs.
5. Create snapshots at the marked point.

Important:
- This script configures the guest OS only.
- vCPU/RAM/disk still need to be set in VirtualBox.
- For the final lab, keep:
  eth0 = management/internet (Kali only)
  eth1 = lab_net / OT
- Do not use bridge for the OT network.
- Do not add a gateway on 192.168.100.0/24.

Network note:
- If a VM cannot reach the internet, the script will stop before apt installs.
  That prevents half-configured systems. For the non-Kali VMs, use a temporary
  management/NAT adapter during initial setup, then remove it after the packages
  are installed and the machine is ready.
