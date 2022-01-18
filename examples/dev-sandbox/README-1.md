### Overview

##### Example:
- dev-sandbox, supplychain-1

##### Use case:
As a developer, every time I make a git commit, I want my source code published as a container image and deployed to Kubernetes using a Deployment and Service configuration.

#### Solution overview:

The following table shows the sequence of activities the Cartographer Supply Chain will orchestrate, as well as the tool you will be using for each activity.
The table shows the Cartographer APIs that will be use to wrap each of the tool resources, and the inputs and outputs it will map from one resource to the next.

In the `Tool Resources` column, the resources in parentheses indicate the secondary resources that  each tool will spawn.
This is helpful for tracking progress and troubleshooting.

| Activity | Tool | Tool Resources | Input | Output | Cartographer Resource |
| --- | --- | --- | --- | --- | --- |
| Detect changes to git source repo | Flux | gitrepository | url, branch | blob url, blob revision | ClusterSourceTemplate |
| Build & publish image | kpack | cnbimage (build, pod) | blob url | image | ClusterImageTemplate |
| Run application | Kubernetes | deployment (replicaset, pod) | image | -- | ClusterTemplate |
| Expose application| Kubernetes | service | -- | -- | ClusterTemplate |

### Install

Submit templates, supply chain, and workload:
```shell
# Install supply chain and templates
ytt -f examples/templates \
    -f examples/dev-sandbox/supplychain-1.yaml \
    --data-values-file config.yaml \
    | kapp deploy -a example-workflows -f- -n default --yes

# Apply workload
ytt -f examples/dev-sandbox/workload-hello-go-1.yaml \
    --data-values-file config.yaml \
    | kubectl apply -f- -n apps-dev
```

### Check Supply Chain

You can make sure the Supply Chain deployed successfully and is ready to be used by running either of the following commands:
```shell
# View Supply Chain status
kapp inspect -a example-workflows --status --filter-kind ClusterSupplyChain
# or
kubectl describe clustersupplychain demo-supplychain
```

To track the progress of the SupplyChain from beginning to end, you can check the status of each of the resources you configured.
Per the template configuration, the Workload name is used to name each resource instance and set a label in each, so you can use either to identify relate resources.
For example:
```shell
kubectl get pod,gitrepository,cnbimage,build,deployment,service --selector app.kubernetes.io/part-of=hello-go-app
```

### Track status

Check workload status:
```shell
kubectl -n apps-dev describe workloads hello-go-web2sandbox-1 
```

You might initially see a status message that says:
> `waiting to read value [.status.latestImage] from resource [image.kpack.io/hello-go-web2sandbox-1] in namespace [apps-dev]`

This likely means the image is still building. You can check the status of the build pod.
Notice the pod is a kpack "build" pod that needs to complete 6 "init" steps.
```shell
kubectl get pod hello-go-web2sandbox-1-build-1-build-pod -n apps-dev
```

When the `STATUS` field reaches a `Completed` state, you can check the workload status again to make sure it has completed without errors.

> Note: You can also use [kp](https://github.com/vmware-tanzu/kpack-cli/blob/main/docs/kp_build_logs.md), the kpack CLI, to see the build log.

#### Check results

You can check the status of the default `all` group of resources.
You should see the usual Deployment, ReplicaSet, Pod, and Service that you ould expect from applying a Deployment and Service configuration to Kubernetes.
```shell
kubectl get all -n apps-dev
```

You can get other resources that play a role in the supplychain.
```shell
kubectl get gitrepository,cnbimage,build,all -n apps-dev
```

```shell
kubectl get pod,gitrepository,cnbimage,build,deployment,service --selector app.kubernetes.io/part-of=hello-go-app
```

You can use `kubectl describe` on any of these to troubleshoot, if necessary.

#### Test the app

You can test the app by starting a port-forward:
```shell
kubectl port-forward svc/hello-go-web2sandbox-1 8080:80 -n apps-dev
```

Then send a request:
```shell
curl localhost:8080
```

#### Clean up

If you started a port-forward to test the app, stop it using `<Ctrl+C>`.

Delete the workflow and workload assets. The application will be deleted together with the workload.
```shell
# Delete Workload
kubectl delete workload hello-go-web2sandbox-1 -n apps-dev
# Delete Supply Chain
kapp delete -a example-workflows -n default --yes
# The following should return "No resources found":
kubectl get workload,clustersupplychain -A
```
