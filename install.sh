#!/usr/bin/env bash
# install.sh - installs Node Recorder as a systemd service on a Debian/Ubuntu
# host: apt packages, AWS CLI v2, service user, bin/ -> /usr/local/bin,
# lib/ -> /usr/local/lib, a config template, and the systemd unit.
# Safe to re-run: skips steps that are already done and never overwrites an
# existing config file.
#
# HAProxy and Stablevisor are both optional on the host: Node Recorder
# already treats "not running" as a per-artifact failure it records and
# continues past, not a fatal error (Failure Handling in
# docs/spec/node-recorder.md).
#
# HAProxy log read needs group membership, granted below only for a group
# that actually exists (a missing group fails the whole unit to start).
# Stablevisor signaling uses AmbientCapabilities=CAP_KILL instead of a
# group, since kill(2) checks UID/capability, not group membership.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_USER="${NODE_RECORDER_USER:-node-recorder}"
CANDIDATE_GROUPS="${NODE_RECORDER_EXTRA_GROUPS:-haproxy}"
CONFIG_FILE="/etc/node-recorder/config"
AWS_CREDENTIALS_FILE="/etc/node-recorder/aws-credentials"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "install.sh must be run as root (sudo $0)" >&2
  exit 1
fi

echo "==> installing packages: jq flock curl tar zcat unzip"
apt-get update
apt-get install -y jq util-linux curl tar gzip unzip

if ! command -v aws >/dev/null 2>&1; then
  echo "==> installing AWS CLI v2"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "${tmp_dir}/awscliv2.zip"
  unzip -q "${tmp_dir}/awscliv2.zip" -d "$tmp_dir"
  "${tmp_dir}/aws/install"
  rm -rf "$tmp_dir"
fi

echo "==> creating service user: ${SERVICE_USER}"
id -u "$SERVICE_USER" >/dev/null 2>&1 \
  || useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"

echo "==> resolving HAProxy log-read group from: ${CANDIDATE_GROUPS}"
RESOLVED_GROUPS=""
for g in $CANDIDATE_GROUPS; do
  if getent group "$g" >/dev/null 2>&1; then
    RESOLVED_GROUPS="${RESOLVED_GROUPS:+$RESOLVED_GROUPS }$g"
  else
    echo "    skipping '$g': no such group on this host (component not installed here)"
  fi
done

echo "==> installing files to /usr/local/bin, /usr/local/lib"
install -d -m 0755 /usr/local/lib /etc/node-recorder \
  /var/lib/node-recorder/state /var/lib/node-recorder/incidents
install -m 0755 "$SCRIPT_DIR"/bin/node-recorder \
  "$SCRIPT_DIR"/bin/capture-stablevisor-pprof.sh \
  "$SCRIPT_DIR"/bin/capture-haproxy-log.sh \
  "$SCRIPT_DIR"/bin/upload-incidents.sh /usr/local/bin/
install -m 0644 "$SCRIPT_DIR"/lib/*.sh /usr/local/lib/
chown -R "${SERVICE_USER}:${SERVICE_USER}" /var/lib/node-recorder

if [[ -f "$CONFIG_FILE" ]]; then
  echo "==> ${CONFIG_FILE} already exists, leaving it untouched"
else
  echo "==> writing config template to ${CONFIG_FILE}"
  install -m 0640 -o "$SERVICE_USER" -g "$SERVICE_USER" /dev/null "$CONFIG_FILE"
  cat > "$CONFIG_FILE" <<'EOF'
# required - node-recorder refuses to start until these are set
PROMETHEUS_URL=
ALERT_NAME=
NODE_ID=
CHAIN=
STABLEVISOR_SNAPSHOT_BASE_DIR=
DAEMON_HOME=

# optional - defaults shown, uncomment to override
# STABLEVISOR_SERVICE_NAME="stablevisor"
# MEMPOOL_TIMEOUT_SECONDS="10"
# HAPROXY_LOG="/var/log/haproxy.log"
# S3_PREFIX="s3://<bucket>/node-recorder"
# SLACK_WEBHOOK_URL=
# LOCAL_RETENTION_COUNT="5"
EOF
fi

if [[ -f "$AWS_CREDENTIALS_FILE" ]]; then
  echo "==> ${AWS_CREDENTIALS_FILE} already exists, leaving it untouched"
else
  echo "==> writing AWS credentials template to ${AWS_CREDENTIALS_FILE}"
  install -m 0600 -o "$SERVICE_USER" -g "$SERVICE_USER" /dev/null "$AWS_CREDENTIALS_FILE"
  cat > "$AWS_CREDENTIALS_FILE" <<'EOF'
# Only needed off AWS (e.g. OVH): there is no instance metadata service to
# hand the AWS CLI a role, so it needs real keys for the S3-upload-only IAM
# user here instead. On EC2, leave this file empty -- the instance profile
# is used automatically and this file is ignored.
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
# AWS_DEFAULT_REGION=
EOF
fi

echo "==> writing /etc/systemd/system/node-recorder.service"
cat > /etc/systemd/system/node-recorder.service <<EOF
[Unit]
Description=Node Recorder - block lag incident capture watcher
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node-recorder
EnvironmentFile=-${AWS_CREDENTIALS_FILE}
Restart=always
RestartSec=5
User=${SERVICE_USER}
Group=${SERVICE_USER}
$( [[ -n "$RESOLVED_GROUPS" ]] && echo "SupplementaryGroups=${RESOLVED_GROUPS}" )

# Lets this service send SIGUSR1 to Stablevisor regardless of what user or
# group it runs as (kill(2) checks UID or CAP_KILL, never group membership).
AmbientCapabilities=CAP_KILL
CapabilityBoundingSet=CAP_KILL

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/lib/node-recorder /run/node-recorder.lock

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node-recorder

echo "==> done. Fill in ${CONFIG_FILE} (and ${AWS_CREDENTIALS_FILE} if this host is not on AWS), then: systemctl start node-recorder"
