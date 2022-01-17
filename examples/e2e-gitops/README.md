### Overview

##### Example:
- e2e-gitops, supplychain
- e2e-gitops, delivery

##### Use case:
As a developer, every time I make a git commit, I want my source code tested and published as a container image. In addition, I want the configuration for a corresponding Knative Service to be delivered (written) to an "ops" git repository.

As a developer and/or app operator, every time there is new delivery (git commit) of ops configuration, I want the configuration submitted to a target Kubernetes cluster.

### Install

Submit templates, supply chain, delivery, workload, and deliverable:
```shell
# Install supply chain and templates
ytt -f examples/templates \
    -f examples/e2e-gitops/supplychain.yaml \
    -f examples/e2e-gitops/delivery.yaml \
    --data-values-file config.yaml \
    | kapp deploy -a example-workflows -f- -n default --yes

# Apply workload to default namespace
ytt -f examples/e2e-gitops/workload-hello-go.yaml \
    --data-values-file config.yaml \
    | kubectl apply -f- -n default

# Apply deliverable to dev (use namespace to simulate a dev cluster)
ytt -f examples/e2e-gitops/deliverable-hello-go.yaml \
    --data-values-file config.yaml \
    | kubectl apply -f- -n apps-dev
```

### Track supply chain status

Check workload status:
```shell
kubectl -n default describe workload hello-go-web2git
```

As in the `dev-sandbox` examples, you might initially see status messages that indicate the code is being tested or the image is being built.

In this case, you may also see a status indicating the configuration is being written to the ops git repo:
> `waiting to read value [.status.outputs.url] from resource [runnable.carto.run/hello-go-web2git-git-writer] in namespace [default]`

If you see this message, you can check the status of the git-writer pod (update the random character in the pod name to match yours):
```shell
kubectl -n default describe pod hello-go-web2git-git-writer-git-cli-dc2wh-pod
```

When the `STATUS` field reaches a `Completed` state, you can check the workload status again to make sure it has completed without errors.

#### Check supply chain results

You can check the status of the default `all` group of resources.
```shell
kubectl get all -n default
```

In contrast to the `dev-sandbox` examples, you will only see the three pods that are part of the supply chain (test, build, git-writer).
The app itself will not be deployed to same namespace.
This is because this supply chain does not apply the ops configuration to the cluster.
Rather, it writes the configuration to the ops git repo.

Check your ops repository (`cartographer-demo-ops`, per the instructions in the setup).
You should see a new branch named after the workload (hello-go-web2git) and containing a manifest file with the deployment configuration.

This git commit is the final product of the supply chain.

### Track dev delivery status

At the beginning of this example, you installed delivery and deliverable resources. These are the counterparts to supply chain and workload for applying configuration to any number of Kubernetes target environments.

Check the status of the deliverable in the dev namespace:
```shell
kubectl describe deliverable hello-go-from-git -n apps-dev 
```

#### Check delivery results

You can check the status of the default `all` group of resources.

```shell
kubectl get all -n apps-dev
```

You should see all the resources that Knative Serving automatically creates, similar what you saw in example `dev-sandbox, supplychain2`.

You can get other resources that play a role in the delivery.
```shell
kubectl get gitrepository,app,kservice,all -n apps-dev
```

You can use `kubectl describe` on any of these to troubleshoot, if necessary.

#### Test the dev app

You can test the app by starting a port-forward:
```shell
kubectl port-forward deployment/hello-go-web2git-00001-deployment 8080:8080 -n apps-dev
```

Then send a request:
```shell
curl localhost:8080
```

#### Promote to production

When you are satisfied that the app is working well in dev, promote it to prod by applying the same delivery to the prod environment:
```shell
ytt -f examples/e2e-gitops/deliverable-hello-go.yaml \
--data-values-file config.yaml \
| kubectl apply -f- -n apps-prod
```

Use the commands above to check the status of the deliverable and other resources that are part of the delivery and of the application. You can test the app in prod as well.

#### Clean up

If you started a port-forward to test the app, stop it using `<Ctrl+C>`.

Delete the workflow and workload assets. The application will be deleted together with the workload.
```shell
# Delete Deliverables
kubectl delete deliverable hello-go-from-git -n apps-prod
kubectl delete deliverable hello-go-from-git -n apps-dev
# Delete Workload
kubectl delete workload hello-go-web2git -n default
# Delete Supply Chain and Delivery
kapp delete -a example-workflows -n default --yes
# The following should return "No resources found":
kubectl get workload,clustersupplychain,deliverable,clusterdelivery -A
```