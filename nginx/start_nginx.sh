#!/bin/sh
#
# Entry point script for the Nginx container in the Stage‑2 blue/green
# deployment.  This script selects the appropriate Nginx configuration template based on the ACTIVE_POOL environment variable, substitutes environment variables into the template, and starts Nginx in the foreground.  The following environment variables influence behaviour:
#   ACTIVE_POOL – either "blue" or "green" (defaults to blue)
#   PORT        – port that the app listens on inside its container

# The templates live in /etc/nginx/templates and are mounted read‑only via the Compose file.  The generated configuration is written to /etc/nginx/conf.d/default.conf.

set -eu

# Determine which configuration template to use.  Default to blue
# primary if ACTIVE_POOL is unset.
ACTIVE="${ACTIVE_POOL:-blue}"
TEMPLATE="/etc/nginx/templates/nginx-${ACTIVE}.conf.template"

if [ ! -f "$TEMPLATE" ]; then
  echo "[start_nginx] Missing template: $TEMPLATE" >&2
  exit 1
fi

# Ensure PORT is set (fall back to 80 if empty).  This is used by
# envsubst below.
export PORT="${PORT:-80}"

echo "[start_nginx] Generating Nginx configuration using $TEMPLATE (PORT=$PORT)"

# Create the output directory if it doesn't exist.
mkdir -p /etc/nginx/conf.d

# Render the template.  Only substitute the port placeholder.  The
# template uses the marker '__PORT__' rather than a shell variable in
# order to avoid shell expansion.  sed safely replaces all
# occurrences of '__PORT__' with the value of $PORT.  All other
# variables (e.g. $host, $remote_addr) remain intact for Nginx to
# evaluate at runtime.
sed "s/__PORT__/$PORT/g" "$TEMPLATE" > /etc/nginx/conf.d/default.conf

# Display the generated config for debugging.
echo "[start_nginx] Rendered /etc/nginx/conf.d/default.conf:" >&2
cat /etc/nginx/conf.d/default.conf >&2

# Start nginx in the foreground.  Use the provided entrypoint syntax so
# that signals are properly forwarded.
exec nginx -g 'daemon off;'