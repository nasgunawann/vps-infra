# VPS Architecture Template

A lightweight, production-ready VPS template designed for low-end servers.

## Directory Layout
* `/opt/vps-architecture` - System infrastructure (Proxy, Logs, Management core, Monitors).
* `/www/<client-site>` - Client web applications hosted on this VPS (cloned separately).

## Core Infrastructure
* **Nginx Proxy Manager (`npm/`)**: Reverse proxy & SSL manager. Public ports `80` and `443` only; admin portal bound to localhost.
* **Dozzle (`dozzle/`)**: Real-time browser-based logs (connected via secure socket proxy).
* **Komodo (`komodo/`)**: Container build & deploy server using FerretDB v2 (PostgreSQL DocumentDB).
* **Uptime Kuma (`uptime/`)**: Uptime and health monitor (accessible via Tailscale VPN tunnel).
* **Docker Socket Proxy (`socket-proxy/`)**: Restricted TCP gateway for `docker.sock` to prevent Dozzle and Komodo from having root host access.

---

## Setup & Deployment Instructions

### 1. Clone into `/opt`
Clone the repository and set ownership to your user:
```bash
sudo mkdir -p /opt
sudo git clone <your-repo-url> /opt/vps-architecture
sudo chown -R $USER:$USER /opt/vps-architecture
cd /opt/vps-architecture
```

### 2. Run Setup Script
Make the setup script executable and run it to verify prerequisites, check for Swap memory, create external networks, prompt for your admin username, and automatically generate all JWT/database secrets:
```bash
chmod +x setup.sh
./setup.sh
```
*The setup script will output your randomly generated administrative credentials. Keep them safe.*

### 3. Start Infrastructure
At the end of `setup.sh`, you will be prompted to start the containers automatically. Alternatively, you can start the core infrastructure manually:
```bash
# 1. Docker socket security gateway
docker compose -f socket-proxy/docker-compose.yml up -d

# 2. Reverse proxy
docker compose -f npm/docker-compose.yml up -d

# 3. Log viewer, health monitors, and manager
docker compose -f dozzle/docker-compose.yml up -d
docker compose -f uptime/docker-compose.yml up -d
docker compose -f komodo/docker-compose.yml up -d
```

### 4. Accessing the Nginx Proxy Manager Console
Since NPM's admin port `81` is bound to `127.0.0.1` (localhost) for security, you cannot access it directly via your public IP. To access it for the first time:

1. **Open an SSH Tunnel** from your local machine:
   ```bash
   ssh -L 8181:127.0.0.1:81 your-vps-user@your-vps-ip
   ```
2. **Open your browser** and navigate to `http://localhost:8181`.
3. **Login with NPM default credentials**:
   * Email: `admin@example.com`
   * Password: `changeme`
   *(You will be prompted to change these immediately).*

---

## Tailscale & Security Integration (Access Lists)

To secure the admin dashboards (NPM admin, Dozzle, Komodo, Uptime Kuma) without exposing them to the public internet:

### 1. Install Tailscale on the VPS host:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### 2. Create the Tailscale IP Access List in Nginx Proxy Manager:
1. Log in to the **Nginx Proxy Manager Admin Console** (forwarded through your SSH tunnel or via Tailscale IP if port 81 is bound to localhost).
2. Go to **Access Lists** -> **Add Access List**.
3. Name it **"Tailscale Only"** and set satisfy to **Any**.
4. In the **Access** tab:
   * Allow: `100.64.0.0/10` (Tailscale private subnet).
   * Deny: `all` (blocks all public internet traffic).
5. Save the list.

### 3. Apply the Access List to Admin Services:
When proxying your management tools (e.g. `komodo.yourdomain.com`), apply the **"Tailscale Only"** Access List on the Proxy Host setup screen. This blocks access from standard public networks while keeping them instantly accessible when you are connected to Tailscale.

---

## Deploying Client Web Applications
Since client websites are managed as separate repositories, clone them separately inside the `/www` directory (e.g. `/www/client-site-a/`):

```bash
sudo mkdir -p /www
sudo chown -R $USER:$USER /www
cd /www
git clone <client-repo-url> client-site-a
```

To route the application through the proxy:
1. Add `proxy-network` as an external network to the client app's `docker-compose.yml`:
   ```yaml
   services:
     web:
       image: nginx:alpine
       container_name: client-site-a-web
       restart: unless-stopped
       networks:
         - proxy-network

   networks:
     proxy-network:
       external: true
   ```
2. Do **not** expose host ports (e.g., `80:80`).
3. Log in to **Nginx Proxy Manager Admin Console** (port 81), add a new Proxy Host:
   * **Domain:** `client-site-a.com`
   * **Scheme:** `http`
   * **Forward HostName:** `client-site-a-web`
   * **Forward Port:** `80`
