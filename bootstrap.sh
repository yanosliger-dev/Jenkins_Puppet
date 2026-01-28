#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8000}"

log() { echo "[$(date +'%F %T')] $*"; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: run as root (use sudo)." >&2
    exit 1
  fi
}

detect_os_like() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${ID_LIKE:-$ID}"
  else
    echo "unknown"
  fi
}

# Resolve puppet binary reliably (works for distro puppet and puppet-agent installs)
find_puppet() {
  if command -v puppet >/dev/null 2>&1; then
    echo "$(command -v puppet)"
    return 0
  fi
  if [[ -x /opt/puppetlabs/bin/puppet ]]; then
    echo "/opt/puppetlabs/bin/puppet"
    return 0
  fi
  if [[ -x /usr/local/bin/puppet ]]; then
    echo "/usr/local/bin/puppet"
    return 0
  fi
  return 1
}

disable_broken_jenkins_repo_debian() {
  local repo="/etc/apt/sources.list.d/jenkins.list"
  local disabled="/etc/apt/sources.list.d/jenkins.list.disabled"  # NOT .list

  [[ -f "$repo" ]] || return 0
  [[ -f "$disabled" ]] && return 0

  # Only disable if apt update output indicates Jenkins repo signature/key problems
  if apt-get update 2>&1 | grep -Eqi 'pkg\.jenkins\.io|NO_PUBKEY|not signed|EXPKEYSIG|BADSIG'; then
    echo "[bootstrap] Jenkins repo appears broken; disabling $repo"
    mv "$repo" "$disabled" || true
  fi
}

install_puppet_debian() {
  log "Detected Debian/Ubuntu. Installing Puppet..."

  disable_broken_jenkins_repo_debian

  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release

  # Prefer distro puppet if present
  if apt-cache show puppet >/dev/null 2>&1; then
    apt-get install -y puppet
    return
  fi

  # Fallback to Puppetlabs repo (puppet-agent)
  log "Puppet package not found in default repos; adding Puppetlabs repo..."
  curl -fsSL https://apt.puppet.com/DEB-GPG-KEY-puppet-20250406 | gpg --dearmor -o /usr/share/keyrings/puppet.gpg
  codename="$(lsb_release -cs)"
  echo "deb [signed-by=/usr/share/keyrings/puppet.gpg] https://apt.puppet.com ${codename} puppet7" > /etc/apt/sources.list.d/puppet.list
  apt-get update -y
  apt-get install -y puppet-agent
  # (No symlink required; we resolve the binary reliably via find_puppet)
}

install_puppet_redhat() {
  log "Detected RHEL-family. Installing Puppet..."
  dnf -y install ca-certificates curl

  # Try distro puppet first (may not exist on EL9)
  if dnf -y install puppet; then
    return
  fi

  # Fallback to Puppetlabs repo (puppet-agent)
  log "Distro puppet not available; enabling Puppetlabs repo..."
  major="$(rpm -E %rhel)"
  dnf -y install "https://yum.puppet.com/puppet7-release-el-${major}.noarch.rpm"
  dnf -y install puppet-agent
  # (No symlink required; we resolve the binary reliably via find_puppet)
}

fetch_manifest() {
  local dest="/root/jenkins8000.pp"

  if [[ -f "./jenkins8000.pp" ]]; then
    log "Using local manifest ./jenkins8000.pp"
    cp -f ./jenkins8000.pp "$dest"
    return
  fi

  if [[ -n "${MANIFEST_URL:-}" ]]; then
    log "Downloading manifest from MANIFEST_URL=${MANIFEST_URL}"
    curl -fsSL "${MANIFEST_URL}" -o "$dest"
    return
  fi

  echo "ERROR: Could not find ./jenkins8000.pp and MANIFEST_URL is not set." >&2
  exit 1
}

run_puppet() {
  log "Running Puppet manifest..."

  local puppet_bin
  if ! puppet_bin="$(find_puppet)"; then
    echo "ERROR: puppet not found even after installation." >&2
    echo "Tried: puppet in PATH, /opt/puppetlabs/bin/puppet, /usr/local/bin/puppet" >&2
    exit 1
  fi

  "$puppet_bin" --version
  "$puppet_bin" apply /root/jenkins8000.pp
}

verify_jenkins_port() {
  log "Verifying Jenkins is listening on port ${PORT}..."
  for i in {1..90}; do
    if ss -lntp 2>/dev/null | grep -q ":${PORT}"; then
      log "OK: Jenkins is listening on ${PORT}"
      return 0
    fi
    sleep 2
  done

  log "ERROR: Jenkins did not bind to port ${PORT} within expected time."
  log "Diagnostics:"
  systemctl status jenkins --no-pager || true
  journalctl -u jenkins --no-pager -n 200 || true
  exit 2
}

main() {
  need_root
  os_like="$(detect_os_like)"

  case "$os_like" in
    *debian*|*ubuntu*)
      install_puppet_debian
      ;;
    *rhel*|*fedora*|*centos*)
      install_puppet_redhat
      ;;
    *)
      echo "ERROR: Unsupported OS. Need Ubuntu/Debian or RHEL-family." >&2
      exit 1
      ;;
  esac

  fetch_manifest
  run_puppet
  verify_jenkins_port

  log "All done. Try: curl -I http://localhost:${PORT}/login"
}

main "$@"

