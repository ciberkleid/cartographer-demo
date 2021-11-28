# Update/download dependencies
vendir sync

# Create cluster and registry
KIND_VERSION=v1.22.4 ./infra-cluster/kind-setup.sh

# Create common secret and service account for registry push/pull access
# Use env var YTT_registry__password to get password from an env var
ytt -f infra-platform/base-creds --data-values-file values-overrides.yaml --data-values-env YTT | kapp deploy --yes -a cicd-creds -f-

# Install CI/CD tooling
ytt -f infra-platform/base-vendir/cert-manager | kapp deploy --yes -a cert-manager -f-
ytt -f infra-platform/base-vendir/cartographer -f infra-platform/overlay/cartographer | kapp deploy --yes -a cartographer -f-
ytt -f infra-platform/base-vendir/tekton | kapp deploy --yes -a tekton -f-
ytt -f infra-platform/base-vendir/kpack -f infra-platform/overlay/kpack --data-values-file values-overrides.yaml | kapp deploy --yes -a kpack -f-
ytt -f infra-platform/base-vendir/flux2 | kapp deploy --yes -a flux2 -f-
ytt -f infra-platform/base-vendir/kapp-controller -f infra-platform/overlay/kapp-controller | kapp deploy --yes -a kapp-controller -f-
ytt -f infra-platform/base-vendir/knative-serving | kapp deploy --yes -a knative-serving -f-

# On kind cluster, use extraPortMappings to allow access to Ingress through port 80/443 on the Laptop.
#curl -sL https://github.com/projectcontour/contour/raw/main/examples/kind/kind-expose-port.yaml > kind-expose-port.yaml
#kind create cluster --config kind-expose-port.yaml
#kubectl apply -f https://projectcontour.io/quickstart/contour.yaml