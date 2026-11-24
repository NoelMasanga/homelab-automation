# Homelab Automation

Automation and platform tooling that runs the lab and automates day-to-day operations.

## Overview
- **Backup/replication:** scheduled snapshot-and-push backups with offsite replication (key-based transport)
- **Certificate upkeep:** automated TLS cert renewal + sync (timer-driven)
- **Agent automation:** a self-hosted AI agent (Hermes) automating backup, DNS, monitoring and certificate workflows; Telegram remote control
- **Cloud-security tooling:** posture scanning on a simulated cloud environment (e.g., Prowler/PMapper-style)
- **Job-search agent:** a recruiter-style agent scanning job boards for remote/hybrid security roles and delivering daily briefings (approval-gated — never auto-submits)

## Repo layout (sanitized)
- `backup/` — backup & replication scripts
- `cert-sync/` — certificate automation
- `agents/` — AI/dashboard automation & the job-search agent skill
- `scan/` — cloud security posture tooling
- `docs/` — runbooks

> Security: **sanitized** public export — no secrets/tokens/keys/internal addresses. See `SANITIZE.md`.

## Tech
Bash · Python · systemd timers · SSH keys · Telegram Bot API

---
© Noel Masanga — shared for demonstration of skills. Reach me at noel@quescom.co.zw
