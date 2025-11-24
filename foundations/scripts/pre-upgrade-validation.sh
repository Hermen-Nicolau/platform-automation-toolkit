#!/usr/bin/env bash
set -euo pipefail

# Paths to your files
STATE_FILE="state.yml"
OPSMAN_FILE="opsman.yml"

# Extract VM name from state.yml
VM_NAME=$(om interpolate --config "${STATE_FILE}" --path /vm_id)

# Extract expected OpsMan IP from opsman.yml
EXPECTED_IP=$(om interpolate -c opsman.yml --path /opsman-configuration/vsphere/private_ip -s)


echo "Checking VM '${VM_NAME}' against expected OpsMan IP '${EXPECTED_IP}'..."

# Use govc to get the VM's IP
ACTUAL_IP=$(govc vm.info -json "${VM_NAME}" | jq -r '.VirtualMachines[0].Guest.IpAddress')

if [[ -z "${ACTUAL_IP}" ]]; then
  echo i"Could not retrieve IP for VM '${VM_NAME}' via govc."
  exit 1
fi

echo "The vCenter reports the VM IP: ${ACTUAL_IP}"

# Compare
if [[ "${ACTUAL_IP}" == "${EXPECTED_IP}" ]]; then
  echo "✅ IP check passed: Reported vCenter VM IP matches opsman.yml"
else
  echo "❌ IP mismatch!"
  echo "   vCenter VM IP:    ${ACTUAL_IP}"
  echo "   Expected IP:      ${EXPECTED_IP}"
  exit 1
fi
