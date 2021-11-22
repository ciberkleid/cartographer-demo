# Remove dependencies and cartographer

#kubectl delete -f https://projectcontour.io/quickstart/contour.yaml

kapp delete -a knative-serving --yes
kapp delete -a kapp-controller --yes
kapp delete -a gitops-toolkit --yes
kapp delete -a kpack --yes
kapp delete -a tekton --yes
kapp delete -a cartographer --yes
kapp delete -a cert-manager --yes
kapp delete -a cicd-creds --yes
