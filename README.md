# Zen Kiosk

A minimal Fedora setup script to turn any system into a self-maintaining **Wayland kiosk** running [Zen Browser](https://zen-browser.app) inside [Cage](https://github.com/Hjdskes/cage).

This script:
- Installs **Cage** (Wayland single-app compositor)
- Installs **Zen Browser** via **Flatpak** (`app.zen_browser.zen`)
- Enables **auto-updates** for both Flatpaks and RPMs
- Disables **SSH** (for SOC2 compliance)
- Ensures a **kiosk user** exists and auto-logs in on TTY1
- Configures that user to launch Cage + Zen automatically on login

---

## Quick Start

Run this on a minimal Fedora install (as root or with `sudo`):

```bash
curl -fsSL https://raw.githubusercontent.com/JackBinary/zen-kiosk/main/setup.sh | sudo KIOSK_URL="https://example.com" bash
```
