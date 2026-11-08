# Deploy the fleet backend on Vultr

**[MLH] Best Use of Vultr.** The MongoDB Atlas backend (and the
optional Tiger Data sink) runs as one small Docker container — sized
for Vultr's cheapest Cloud Compute tier.

## Steps

1. Sign up at vultr.com and claim the MLH hacker credits.
2. **Deploy New Instance → Cloud Compute**: Ubuntu 24.04, the
   smallest regular plan, any US region (Dallas is closest to UTD).
   Paste `cloud-init.yaml` into the user-data / Cloud Init field.
3. When it boots, SSH in and finish the one manual step (the Atlas
   password deliberately never travels through cloud-init):

   ```sh
   nano /opt/swat/deploy/.env   # set MONGODB_URI
   cd /opt/swat/deploy && docker compose up -d --build
   ```

4. Allow port **8787** in the Vultr firewall / on the instance.
5. Verify: `curl http://<instance-ip>:8787/health` → `{"ok":true,...}`
6. Point the app at it:

   ```sh
   flutter run --dart-define=FLEET_BACKEND_URL=http://<instance-ip>:8787
   ```

The Photon Fleet Line service (`../photon/`) can ride the same
instance the same way — it's a second Node process; give it its own
port and process manager.
