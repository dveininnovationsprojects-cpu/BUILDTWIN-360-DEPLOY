# Production setup steps (VM, firewall, DNS, TLS, secrets, Jenkins credentials)

Do these in order. They need your cloud account, DNS and Jenkins logins, so they are done by you.

## 1. Create the VM
- Ubuntu 22.04 LTS or later, 2 vCPU, 4 GB RAM, 40 GB disk or more, in a region near Chennai (for example Mumbai).
- Add your SSH public key when creating it. Note the public IP address.

## 2. Firewall (cloud security group)
| Port | Source |
|------|--------|
| 22   | your office/home IP only |
| 80   | anywhere (needed for certificate issue) |
| 443  | anywhere |

Do not open 5432 or 8080.

## 3. DNS
- Create an A record: `buildtwin.<your-domain>` -> the VM public IP. Wait until `nslookup buildtwin.<your-domain>` returns that IP.

## 4. Prepare the VM (ssh in as the admin user)
```bash
sudo apt-get update && sudo apt-get install -y ca-certificates curl git openssl
curl -fsSL https://get.docker.com | sudo sh
sudo adduser --disabled-password --gecos "" deploy
sudo usermod -aG docker deploy
sudo mkdir -p /home/deploy/.ssh
```
Generate a key pair for Jenkins on your PC (`ssh-keygen -t ed25519 -f buildtwin-prod-deploy`), then put the contents of
`buildtwin-prod-deploy.pub` into `/home/deploy/.ssh/authorized_keys` (owner `deploy`, mode 600).

## 5. Get the code and create the secrets (as `deploy`)
```bash
sudo mkdir -p /opt/buildtwin && sudo chown deploy:deploy /opt/buildtwin
git clone https://github.com/dveininnovationsprojects-cpu/BUILDTWIN-360-DEPLOY.git /opt/buildtwin
cd /opt/buildtwin && chmod +x prod/*.sh
./prod/gen-secrets.sh buildtwin.<your-domain>
```
The script writes `prod/.env.prod` (mode 600) with new random values and prints none of them.
Keep a copy of the file in your password manager. Do not commit it.

## 6. TLS
Nothing to install: Caddy requests and renews the certificate on first start, once DNS points at the VM and ports 80 and 443 are open.
Check after the first deploy: `curl -I https://buildtwin.<your-domain>`.

## 7. Jenkins credentials (Manage Jenkins > Credentials > Global > Add)
| ID | Kind | Value |
|----|------|-------|
| `buildtwin-prod-ssh` | SSH Username with private key | username `deploy`, private key = contents of `buildtwin-prod-deploy` |
| `buildtwin-prod-domain` | Secret text | `buildtwin.<your-domain>` |
| `buildtwin-prod-admin-password` | Secret text | output of `grep '^APP_SEED_ADMIN_PASSWORD=' prod/.env.prod \| cut -d= -f2-` on the VM |

Also accept the VM host key once from the Jenkins host: `ssh deploy@<vm-ip>`.

## 8. Run it
Create the job from `Jenkinsfile.prod`, run it with the tags and `PROD_HOST`, approve, then send the log so the Phase 10 records can be updated.
Do not go live with `APP_SEED_ENABLED=true` while KTI-02 is open.
