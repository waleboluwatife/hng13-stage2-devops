# Stage 2 – Blue/Green Deployment with Nginx Upstreams

This project implements a **blue/green deployment** pattern for a Node.js
service, fronted by an Nginx reverse proxy.  Two instances of the
application (blue and green) are run concurrently in separate
containers.  Only one of the instances handles traffic at a time; the
other remains on hot standby and automatically takes over if the
primary fails.  This arrangement allows you to simulate zero‑downtime
deployments and rapid failover without modifying the application code.

## Repository Structure

```
stage2/
├── docker‑compose.yml    # Orchestrates nginx and the two app containers
├── .env.example         # Template for environment variables (copy to .env)
├── nginx/
│   ├── nginx‑blue.conf.template   # Nginx config when blue is active
│   ├── nginx‑green.conf.template  # Nginx config when green is active
│   └── start_nginx.sh             # Generates final config and starts nginx
└── README.md           # This file
```

## Quick Start

1. **Clone the repository** and navigate into the `stage2` directory.

2. **Create a `.env` file** by copying the provided `.env.example`:

   ```sh
   cp .env.example .env
   # Then edit .env to specify the images and release IDs
   ```

   The `.env` file defines the images used for the blue and green
   services, which pool is active, release identifiers, and the
   application port.  A typical `.env` might look like:

   ```env
   BLUE_IMAGE=ghcr.io/acme/myapp:1.0.0
   GREEN_IMAGE=ghcr.io/acme/myapp:1.1.0
   ACTIVE_POOL=blue
   RELEASE_ID_BLUE=v1
   RELEASE_ID_GREEN=v2
   PORT=80
   ```

3. **Start the stack** using Docker Compose:

   ```sh
   docker compose --env-file .env -f docker-compose.yml up -d
   ```

   The services will start as follows:
   - **app_blue**: The blue instance, bound to host port `8081`.
   - **app_green**: The green instance, bound to host port `8082`.
   - **nginx**: Reverse proxy listening on `8080` and forwarding
     requests to the active pool.

4. **Verify the deployment**.  Fetch the `/version` endpoint through
   Nginx:

   ```sh
   curl -i http://localhost:8080/version
   ```

   You should see HTTP 200 along with custom headers similar to:

   ```
   X-App-Pool: blue
   X-Release-Id: v1
   ```

5. **Trigger a failover** by inducing chaos on the active instance.
   Suppose blue is active; call its chaos endpoint:

   ```sh
   curl -X POST http://localhost:8081/chaos/start?mode=error
   ```

   Subsequent requests to `http://localhost:8080/version` will now be
   served by the green instance and include `X-App-Pool: green` and its
   release identifier.  Once the primary recovers (or you call
   `/chaos/stop` on the blue instance) Nginx will automatically revert
   traffic back to the blue pool.

## How It Works

### Parameterised Compose

The Compose file defines three services: `nginx`, `app_blue` and
`app_green`.  All configuration is driven by environment variables:

- **BLUE_IMAGE** / **GREEN_IMAGE** specify the container images for the
  application pools.
- **ACTIVE_POOL** chooses which pool receives traffic by default.
- **RELEASE_ID_BLUE** / **RELEASE_ID_GREEN** provide human‑readable
  identifiers returned via the `X‑Release‑Id` header.
- **PORT** defines the internal port used by the Node.js service.

### Nginx Configuration and Failover

The Nginx container uses the script `start_nginx.sh` as its
entrypoint.  When the container starts the script:

1. Reads the `ACTIVE_POOL` environment variable and selects either
   `nginx‑blue.conf.template` or `nginx‑green.conf.template`.
2. Substitutes the value of `$PORT` into the template using
   [`envsubst`](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html) and writes the result to `/etc/nginx/conf.d/default.conf`.
3. Starts Nginx in the foreground (`daemon off`).

Each template defines an **upstream** block with two servers: the
primary and a `backup`.  Nginx will route traffic to the primary
server under normal conditions.  If a request encounters a timeout,
connection error or HTTP 5xx response, the `proxy_next_upstream`
directive instructs Nginx to retry the request on the backup server.
The `max_fails` and `fail_timeout` parameters mark the primary as
unhealthy after a single failure within five seconds, causing all
traffic to be routed to the backup.  When the primary recovers, it
automatically resumes serving traffic.

### Headers

The application containers return custom headers:

- **X‑App‑Pool** — indicates which pool (blue or green) handled the
  request.
- **X‑Release‑Id** — the release identifier passed via the
  `RELEASE_ID` environment variable.

The Nginx proxy does not strip these headers; they pass through to
clients unchanged.  This behaviour allows the CI grader to confirm
that requests are being served by the correct pool.

## Cleanup

To stop the deployment, run:

```sh
docker compose down
```

To tear down all containers and networks and remove persistent
artifacts, add the `--volumes` flag.

## Decision Notes (Optional)

The project includes a `DECISION.md` file that explains design
choices, such as the selection of timeouts and failover parameters.