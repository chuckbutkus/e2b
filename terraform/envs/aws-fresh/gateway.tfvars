# Gateway API plan — exercises feature/gateway-api additions.
# All other variables use the defaults in variables.tf.

# Install NGINX Gateway Fabric alongside ingress-nginx (coexistence mode).
# Both controllers run; ingress-nginx continues handling Ingress resources
# and ACME challenges while new workloads adopt HTTPRoute.
install_nginx_gateway_fabric = true

# Set to your real email to create letsencrypt-staging and letsencrypt-prod
# ClusterIssuers. Leave empty to install cert-manager without any issuers.
acme_email = "ops@example.com"
