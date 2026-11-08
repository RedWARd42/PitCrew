#!/bin/sh
# Vultr Startup Script version of the deploy staging steps — paste
# this into Vultr (Account -> Startup Scripts -> Add Startup Script),
# then select it under "Startup Script" when creating the instance.
# It installs Docker, clones the repo, and stages the env file. One
# manual step remains afterwards (by design — the Atlas password
# never travels through this script):
#   1. SSH in, edit /opt/swat/deploy/.env (set MONGODB_URI)
#   2. cd /opt/swat/deploy && docker compose up -d --build
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
git clone -b mlh-tracks https://github.com/RedWARd42/Swat.git /opt/swat
cp /opt/swat/deploy/.env.example /opt/swat/deploy/.env
echo "Swat staged. Edit /opt/swat/deploy/.env, then docker compose up." > /opt/swat/SETUP.txt
