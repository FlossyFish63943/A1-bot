#!/usr/bin/env bash
set -u
BOOT_GB=200
echo "$SSH_PUBLIC_KEY" > /tmp/key.pub

IMAGE_OCID=$(oci compute image list --compartment-id "$OCI_TENANCY" \
  --operating-system "Canonical Ubuntu" --operating-system-version "24.04" \
  --shape VM.Standard.A1.Flex --sort-by TIMECREATED --sort-order DESC \
  --limit 1 --query 'data[0].id' --raw-output)

AGENT='{"isMonitoringDisabled":false,"isManagementDisabled":true,"areAllPluginsDisabled":false,"pluginsConfig":[
{"name":"Vulnerability Scanning","desiredState":"DISABLED"},
{"name":"Compute Instance Monitoring","desiredState":"ENABLED"},
{"name":"Custom Logs Monitoring","desiredState":"ENABLED"},
{"name":"Compute Instance Run Command","desiredState":"ENABLED"},
{"name":"Cloud Guard Workload Protection","desiredState":"ENABLED"},
{"name":"Bastion","desiredState":"DISABLED"},
{"name":"Block Volume Management","desiredState":"DISABLED"},
{"name":"Management Agent","desiredState":"DISABLED"}]}'

for AD in $(oci iam availability-domain list --compartment-id "$OCI_TENANCY" \
            --query 'data[].name' | jq -r '.[]'); do
  out=$(oci compute instance launch \
    --availability-domain "$AD" \
    --compartment-id "$COMPARTMENT_OCID" \
    --display-name ServerV3 \
    --shape VM.Standard.A1.Flex \
    --shape-config '{"ocpus":2,"memoryInGBs":12}' \
    --image-id "$IMAGE_OCID" \
    --subnet-id "$SUBNET_OCID" \
    --vnic-display-name SV3_VNIC \
    --assign-public-ip true \
    --boot-volume-size-in-gbs "$BOOT_GB" \
    --boot-volume-vpus-per-gb 10 \
    --is-pv-encryption-in-transit-enabled true \
    --instance-options '{"areLegacyImdsEndpointsDisabled":true}' \
    --agent-config "$AGENT" \
    --ssh-authorized-keys-file /tmp/key.pub 2>&1); rc=$?

  if [ $rc -eq 0 ]; then
    curl -s -H "Email: aaronabrm@gmail.com" -d "Oracle VM ServerV3 created in $AD" "https://ntfy.sh/$NTFY_TOPIC"
    gh workflow disable launch.yml
    exit 0
  fi
  if echo "$out" | grep -qiE "out of (host )?capacity"; then echo "No capacity in $AD"; continue; fi
  if echo "$out" | grep -qiE "TooManyRequests|429"; then sleep 60; continue; fi
  echo "$out"; exit 2   # a real error, fail loudly
done
exit 0