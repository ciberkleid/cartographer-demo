### Overview

##### Example:
- e2e-pkgops, supplychain
- e2e-pkgops, delivery

##### Use case:
This is a variation on example `e2e-gitops`.
In this case, instead of publishing the manifest.yaml file to a git "ops" repo, it is published to an image registry as an "ops" image.

In addition, [Package](https://carvel.dev/kapp-controller/docs/latest/packaging/#package) configuration is published as a separate "package" image.

Thus, all artifacts (app, ops, and package images) are stored in an image registry.
Since the package image contains a reference to the ops image, and the ops image contains a reference to the appimage, the package image can be used as the vehicle for delivery.
Kubernetes will transitively pull the other images into the cluster as well.
The package image is use as the artifact of delivery to target environments.

In this example, the SupplyChain publishes the ops and package images instead of writing the ops configuration to git.
The Delivery installs the package image.

#### Solution overview:

The following table shows the sequence of activities the Cartographer Supply Chain orchestrate, as well as the tool you will be using for each activity.
The table shows the Cartographer APIs that will be use to wrap each of the tool resources, and the inputs and outputs it will map from one resource to the next.

In the `Tool Resources` column, the resources in parentheses indicate the secondary resources that  each tool will spawn.
This is helpful for tracking progress and troubleshooting.

| Activity | Tool | Tool Resources | Input | Output | Cartographer Resource |
| --- | --- | --- | --- | --- | --- |
| Detect changes to git source repo | Flux | gitrepository | url, branch | blob url, blob revision | ClusterSourceTemplate |
| Test source code | Tekton | taskrun (pod) | url, revision | blob url | ClusterSourceTemplate, Runnable, ClusterRunTemplate |
| Build & publish image | kpack | cnbimage (build, pod) | blob url | image | ClusterImageTemplate |
| Generate config | Kubernetes | configmap | image | configmap | ClusterConfigTemplate |
| Publish config as imgpkg to image registry | Tekton | taskrun (pod) | configmap | image | ClusterImageTemplate |

The following table shows the sequence of activities the Cartographer Delivery orchestrate.

| Activity | Tool | Tool Resources | Input | Output | Cartographer Resource |
| --- | --- | --- | --- | --- | --- |
| Detect changes to pkg image repo | Flux | imagerepository, imagepolicy | image repo | image tag | ClusterSourceTemplate |
| Apply ops configuration | Kapp | app (configmap), packagerepository | image | -- | ClusterTemplate |
| Install package | Kapp | app (configmap), packageinstall | package name | -- | ClusterDeploymentTemplate |
| Serve application | Knative | kservice (various - see below) | -- | -- | -- |

### Install

Submit templates, supply chain, delivery, workload, and deliverable:
```shell
# Install supply chain and templates
ytt -f examples/templates \
    -f examples/e2e-pkgops/supplychain.yaml \
    -f examples/e2e-pkgops/delivery.yaml \
    --data-values-file config.yaml \
    | kapp deploy -a example-workflows -f- -n default --yes

# Apply workload to default namespace
ytt -f examples/e2e-pkgops/workload-hello-go.yaml \
    --data-values-file config.yaml \
    | kubectl apply -f- -n default

# Apply deliverable to dev (use namespace to simulate a dev cluster)
ytt -f examples/e2e-pkgops/deliverable-hello-go.yaml \
    --data-values-file config.yaml \
    | kubectl apply -f- -n apps-dev
```

### Track supply chain status

Check workload status:
```shell
kubectl -n default describe workload hello-go-web2pkg
```

You should see similar results as in the `e2e-gitops` example.
In this case, however, after the app image has been built, you might catch the status of the workload indicating the configuration is being written to the image registry:
> `waiting to read value [.status.outputs.image] from resource [runnable.carto.run/hello-go-web2pkg-imgpkg-bundle] in namespace [default]`

If you see this message, you can check the status of the imgpkg creator pod (update the random character in the pod name to match yours):
```shell
kubectl -n default get pod hello-go-web2pkg-imgpkg-bundle-imgpkg-push-package-rdkhv-pod
```
You can use the `kubectl logs` and `kubectl describe` commands as well.


When the `STATUS` field reaches a `Completed` state, you can check the workload status again to make sure it has completed without errors.

#### Check supply chain results

You can check the status of the default `all` group of resources.
```shell
kubectl get all -n default
```

As with the `e2e-gitops` example:
- You will see three pods that are part of the supply chain. In this case, they are: test, build, imgpkg.
- The default namespace contains the Supply Chain resources, since you created the workload in this namespace. The app itself will be deployed to the apps-dev namespace, which is where you created the deliverable.

Check your image registry (the one you specified in your `config.yaml`).
You should see three new images for the workload:
- One for the app (built from the source code)
- One for the ops file (manifest.yaml)
- One for the package (Package resource configuration) 

This package image is the final product of the supply chain.

The Package configuration references the ops image, and the ops image contains the manifest.yaml which references the app image. Thus, you only need to deliver the package image to the target Kubernetes cluster.

### Track dev delivery status

At the beginning of this example, you installed delivery and deliverable resources. These are the counterparts to supply chain and workload for applying configuration to any number of Kubernetes target environments.

Check the status of the deliverable in the dev namespace:
```shell
kubectl describe deliverable hello-go-from-pkg -n apps-dev 
```

#### Check delivery results

You can check the status of the default `all` group of resources.

```shell
kubectl get all -n apps-dev
```

You should see all the resources that Knative Serving automatically creates, similar what you saw in example `dev-sandbox, supplychain2`.

You can get other resources that play a role in the delivery.
```shell
kubectl get imagerepository,imagepolicy,packagerepository,packageinstall,app -n apps-dev
```

You can use `kubectl describe` on any of these to troubleshoot, if necessary.

#### Test the dev app

You can test the app by starting a port-forward:
```shell
kubectl port-forward deployment/hello-go-web2pkg-00001-deployment 8080:8080 -n apps-dev
```

Then send a request:
```shell
curl localhost:8080
```

#### Promote to production

When you are satisfied that the app is working well in dev, promote it to prod by applying the same delivery to the prod environment:
```shell
ytt -f examples/e2e-pkgops/deliverable-hello-go.yaml \
--data-values-file config.yaml \
| kubectl apply -f- -n apps-prod
```

Use the commands above to check the status of the deliverable and other resources that are part of the delivery and of the application. You can test the app in prod as well.

#### Clean up

If you started a port-forward to test the app, stop it using `<Ctrl+C>`.

Delete the workflow and workload assets. The application will be deleted together with the workload.
```shell
# Delete Deliverables
kubectl delete deliverable hello-go-from-pkg -n apps-prod
kubectl delete deliverable hello-go-from-pkg -n apps-dev
# Delete Workload
kubectl delete workload hello-go-web2pkg -n default
# Delete Supply Chain and Delivery
kapp delete -a example-workflows -n default --yes
# The following should return "No resources found":
kubectl get workload,clustersupplychain,deliverable,clusterdelivery -A
```