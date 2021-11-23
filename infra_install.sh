# Update/download dependencies
vendir sync

# Create cluster and registry
KIND_VERSION=v1.22.4 ./kind/kind-setup.sh

# Create common secret and service account for registry push/pull access
ytt -f infra/base-creds | kapp deploy --yes -a cicd-creds -f-

# Install CI/CD tooling
ytt -f infra/base-vendir/cert-manager | kapp deploy --yes -a cert-manager -f-
ytt -f infra/base-vendir/cartographer -f infra/overlay/cartographer | kapp deploy --yes -a cartographer -f-
ytt -f infra/base-vendir/tekton | kapp deploy --yes -a tekton -f-
ytt -f infra/base-vendir/kpack -f infra/overlay/kpack | kapp deploy --yes -a kpack -f-
ytt -f infra/base-vendir/gitops-toolkit -f infra/overlay/gitops-toolkit | kapp deploy --yes -a gitops-toolkit -f-
ytt -f infra/base-vendir/kapp-controller -f infra/overlay/kapp-controller | kapp deploy --yes -a kapp-controller -f-
ytt -f infra/base-vendir/knative-serving | kapp deploy --yes -a knative-serving -f-

# On kind cluster, use extraPortMappings to allow access to Ingress through port 80/443 on the Laptop.
#curl -sL https://github.com/projectcontour/contour/raw/main/examples/kind/kind-expose-port.yaml > kind-expose-port.yaml
#kind create cluster --config kind-expose-port.yaml
#kubectl apply -f https://projectcontour.io/quickstart/contour.yaml