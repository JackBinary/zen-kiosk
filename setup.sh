#!/usr/bin/env bash
set -euo pipefail

KIOSK_USER="${KIOSK_USER:-kiosk}"
KIOSK_HOME="/home/${KIOSK_USER}"
GETTY_DIR="/etc/systemd/system/getty@tty1.service.d"
AUTOLOGIN_DROPIN="${GETTY_DIR}/autologin.conf"
BASH_PROFILE="${KIOSK_HOME}/.bash_profile"
FLATPAK_SVC="/etc/systemd/system/flatpak-update.service"
FLATPAK_TIMER="/etc/systemd/system/flatpak-update.timer"
DNF_AUTOMATIC_CFG="/etc/dnf/automatic.conf"
ZEN_APP_ID="app.zen_browser.zen"
KIOSK_URL="${KIOSK_URL:-https://example.com}"

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: run as root (e.g., pipe into: sudo bash)"; exit 1
  fi
}

step() { echo -e "\n==> $*"; }

disable_ssh() {
  step "Disabling SSH (sshd) if installed (SOC2)"
  if systemctl list-unit-files | grep -q '^sshd\.service'; then
    systemctl disable --now sshd || true
    systemctl mask sshd || true
    echo "[OK] sshd disabled + masked."
  else
    echo "[SKIP] sshd not installed."
  fi
}

install_base() {
  step "Installing base packages: cage, flatpak"
  dnf -y install cage flatpak || true
  echo "[OK] cage + flatpak ensured."
}

enable_flathub() {
  step "Ensuring Flathub remote"
  if ! flatpak remotes | awk '{print $1}' | grep -qx flathub; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    echo "[OK] Flathub added."
  else
    echo "[OK] Flathub already present."
  fi
}

install_zen() {
  step "Installing Zen Browser (Flatpak: ${ZEN_APP_ID})"
  if ! flatpak info "${ZEN_APP_ID}" >/dev/null 2>&1; then
    flatpak install -y flathub "${ZEN_APP_ID}"
    echo "[OK] Zen installed."
  else
    echo "[OK] Zen already installed."
  fi
}

ensure_kiosk_user() {
  step "Ensuring kiosk user: ${KIOSK_USER}"
  if ! id "${KIOSK_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${KIOSK_USER}"
    # make passwordless only when we create the user (don’t change existing accounts)
    passwd -d "${KIOSK_USER}" >/dev/null 2>&1 || true
    echo "[OK] Created ${KIOSK_USER} (passwordless)."
  else
    echo "[OK] User ${KIOSK_USER} exists."
  fi
  mkdir -p "${KIOSK_HOME}"
  chown -R "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}"
}

configure_autologin_tty1() {
  step "Configuring autologin on tty1"
  mkdir -p "${GETTY_DIR}"
  cat > "${AUTOLOGIN_DROPIN}" <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin ${KIOSK_USER} --noclear %I \$TERM
Type=simple
EOF
  systemctl daemon-reload
  systemctl enable getty@tty1.service
  echo "[OK] Autologin set for ${KIOSK_USER} on tty1."
}

configure_kiosk_autostart() {
  step "Setting kiosk autostart in ${BASH_PROFILE} (.bash_profile is correct for login shells)"
  install -d -m 0755 "${KIOSK_HOME}"
  touch "${BASH_PROFILE}"
  # remove previous managed block if present
  sed -i '/# >>> zen-kiosk start >>>/,/# <<< zen-kiosk end <<</d' "${BASH_PROFILE}" || true

  cat >> "${BASH_PROFILE}" <<'EOF'
# >>> zen-kiosk start >>>
# Auto-start Cage + Zen Browser when logging into tty1 and no Wayland session is active.
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec cage -s -- flatpak run app.zen_browser.zen --new-window __KIOSK_URL__
fi
# <<< zen-kiosk end <<<
EOF
  sed -i "s|__KIOSK_URL__|${KIOSK_URL}|g" "${BASH_PROFILE}"
  chown "${KIOSK_USER}:${KIOSK_USER}" "${BASH_PROFILE}"
  chmod 0644 "${BASH_PROFILE}"
  echo "[OK] Autostart configured."
}

setup_flatpak_updates() {
  step "Enabling daily Flatpak auto-updates (systemd timer)"
  cat > "${FLATPAK_SVC}" <<'EOF'
[Unit]
Description=Flatpak automatic updates

[Service]
Type=oneshot
ExecStart=/usr/bin/flatpak update -y --noninteractive
EOF

  cat > "${FLATPAK_TIMER}" <<'EOF'
[Unit]
Description=Daily Flatpak update

[Timer]
OnBootSec=5min
OnUnitActiveSec=1d
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now flatpak-update.timer
  echo "[OK] Flatpak auto-update timer active."
}

setup_dnf_automatic() {
  step "Enabling dnf-automatic for RPM updates"
  dnf -y install dnf-automatic || true
  if [[ -f "${DNF_AUTOMATIC_CFG}" ]]; then
    sed -i 's/^\s*apply_updates\s*=.*/apply_updates = yes/' "${DNF_AUTOMATIC_CFG}" || true
    sed -i 's/^\s*upgrade_type\s*=.*/upgrade_type = default/' "${DNF_AUTOMATIC_CFG}" || true
  fi
  systemctl enable --now dnf-automatic.timer
  echo "[OK] dnf-automatic timer active."
}

main() {
  require_root
  disable_ssh
  install_base
  enable_flathub
  install_zen
  ensure_kiosk_user
  configure_autologin_tty1
  configure_kiosk_autostart
  setup_flatpak_updates
  setup_dnf_automatic

  echo -e "\n=== SUMMARY ==="
  echo "SSH: disabled (masked if installed)"
  echo "Auto-updates: Flatpak timer + dnf-automatic enabled"
  echo "Installed: cage, flatpak; Flatpak app ${ZEN_APP_ID}"
  echo "User: ${KIOSK_USER} (autologin on tty1)"
  echo "Autostart: ${BASH_PROFILE} (login shell) -> cage -> zen"
  echo "Homepage: ${KIOSK_URL}"
  echo "[DONE] Reboot to test."
}

main "$@"
