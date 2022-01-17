### Overview

##### Example:
- dev-sandbox, supplychain-2

##### Use case:
As a developer, every time I make a git commit, I want my source code tested, published as a container image, and deployed to Kubernetes using a a Knative Service configuration.

### Install

Submit templates, supply chain, and workload:
```shell
# Install supply chain and templates
ytt -f examples/templates \
    -f examples/dev-sandbox/supplychain-2.yaml \
    --data-values-file config.yaml \
    | kapp deploy -a example-workflows -f- -n default --yes

# Apply workload
ytt -f examples/dev-sandbox/workload-hello-go-2.yaml \
    --data-values-file config.yaml \
    | kubectl apply -f- -n apps-dev
```

### Track status

Check workload status:
```shell
kubectl -n apps-dev describe workloads hello-go-web2sandbox-2
```

You might initially see a status message that says:
> `waiting to read value [.status.artifact.url] from resource [gitrepository.source.toolkit.fluxcd.io/hello-go-web2sandbox-2] in namespace [apps-dev]`

This likely means the code is still being tested. You can check the status of the test pod (update the random character in the pod name to match yours):
```shell
kubectl get pod hello-go-web2sandbox-2-test-golang-c4jmz-pod -n apps-dev
```

When the `STATUS` field reaches a `Completed` state, you can check the workload status again.

As with example 1, you may see an indication that the image is building:

> `waiting to read value [.status.latestImage] from resource [image.kpack.io/hello-go-web2sandbox-2] in namespace [apps-dev]`

You can check the status of the build pod:
```shell
kubectl get pod hello-go-web2sandbox-1-build-1-build-pod -n apps-dev
```

When the `STATUS` field of the build pod reaches a `Completed` state, you can check the workload status once again to make sure it has completed without errors.

> Note: You can also use [kp](https://github.com/vmware-tanzu/kpack-cli/blob/main/docs/kp_build_logs.md), the kpack CLI, to see the build log.

#### Check results

You can check the status of the default `all` group of resources.

```shell
kubectl get all -n apps-dev
```

You should see all the resources that Knative Serving creates by default for the deployment of a Knative Service.
It shoul look something like this:
```shell
$ kubectl get all -n apps-dev
NAME                                                           READY   STATUS      RESTARTS   AGE
pod/hello-go-web2sandbox-2-00001-deployment-6bc7449bfc-6nxwl   2/2     Running     0          7m41s
pod/hello-go-web2sandbox-2-build-1-build-pod                   0/1     Completed   0          8m52s
pod/hello-go-web2sandbox-2-test-golang-c4jmz-pod               0/1     Completed   0          9m35s

NAME                                           TYPE           CLUSTER-IP      EXTERNAL-IP                                   PORT(S)                                      AGE
service/hello-go-web2sandbox-2                 ExternalName   <none>          hello-go-web2sandbox-2.apps-dev.example.com   80/TCP                                       7m34s
service/hello-go-web2sandbox-2-00001           ClusterIP      10.96.10.93     <none>                                        80/TCP                                       7m41s
service/hello-go-web2sandbox-2-00001-private   ClusterIP      10.96.208.154   <none>                                        80/TCP,9090/TCP,9091/TCP,8022/TCP,8012/TCP   7m41s

NAME                                                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/hello-go-web2sandbox-2-00001-deployment   1/1     1            1           7m41s

NAME                                                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/hello-go-web2sandbox-2-00001-deployment-6bc7449bfc   1         1         1       7m41s

NAME                                                       LATESTCREATED                  LATESTREADY                    READY   REASON
configuration.serving.knative.dev/hello-go-web2sandbox-2   hello-go-web2sandbox-2-00001   hello-go-web2sandbox-2-00001   True    

NAME                                                 URL                                                  LATESTCREATED                  LATESTREADY                    READY     REASON
service.serving.knative.dev/hello-go-web2sandbox-2   http://hello-go-web2sandbox-2.apps-dev.example.com   hello-go-web2sandbox-2-00001   hello-go-web2sandbox-2-00001   Unknown   IngressNotConfigured

NAME                                               URL                                                  READY     REASON
route.serving.knative.dev/hello-go-web2sandbox-2   http://hello-go-web2sandbox-2.apps-dev.example.com   Unknown   IngressNotConfigured

NAME                                                        CONFIG NAME              K8S SERVICE NAME   GENERATION   READY   REASON   ACTUAL REPLICAS   DESIRED REPLICAS
revision.serving.knative.dev/hello-go-web2sandbox-2-00001   hello-go-web2sandbox-2                      1            True             1                 1

NAME                                        SOURCE                                            SUPPLYCHAIN     READY   REASON
workload.carto.run/hello-go-web2sandbox-2   https://github.com/ciberkleid/go-sample-app.git   dev-sandbox-2   True    Ready
```

You can get other resources that play a role in the supplychain.
```shell
kubectl get gitrepository,taskrun,cnbimage,build,app,all -n apps-dev
```

You can use `kubectl describe` on any of these to troubleshoot, if necessary.

#### Test the app

You can test the app by starting a port-forward:
```shell
kubectl port-forward deployment/hello-go-web2sandbox-2-00001-deployment 8080:8080 -n apps-dev
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
kubectl delete workload hello-go-web2sandbox-2 -n apps-dev
# Delete Supply Chain
kapp delete -a example-workflows -n default --yes
# The following should return "No resources found":
kubectl get workload,clustersupplychain -A
```