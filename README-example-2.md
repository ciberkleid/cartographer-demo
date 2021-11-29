# Example 1: Continuous deployment with kapp controller and Knative

## Prerequisites

This example assumes you have reviewed and understood [example 1](README-example-1.md).

## Swap "batteries"

In example 1, you set up a Supply Chain that creates a Deployment and Service resource per application.
The effect is equivalent to a manual `kubectl apply -f ...`.

However, since designing this Supply Chain, you've gotten excited about some additional tooling that can improve your app operations. Specifically, you want to leverage [kapp controller] and [Knative serving].

> **Note:**
> 
> Don't worry if you're not familiar ith kapp-controller and Knative. You will see some of what these tools offer through this example, and can then explore them further if you are interested.
> 
> It is also worth noting that there are other tools in the ecosystem that could be used instead.

## Create template

You can reuse the _ClusterSourceTemplate_ and _ClusterImageTemplate_ from example 1, which poll an image repository and retrieve new tags.

However, you won't need the _ClusterTemplates_ for Deployment and Service because`Knative serving` will deploy and expose the image automatically.

Instead, you need to provide a new _ClusterTemplate_ that provides a resource of type `service.serving.knative.dev`.
This Knative Service will include the same ContainerSpec as the Deployment template from example 1.

Take a look at the [Knative Service template](example-2/ops/kapp2knative-template.yaml).
Find the following section:
```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: $(workload.metadata.name)$
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "1"
    spec:
      serviceAccountName: service-account
      containers:
        - name: workload
          image: $(images.image.image)$
          env: $(workload.spec.env)$
          resources: $(workload.spec.resources)$
          ports:
            - containerPort: $(params.containerPort)$
          securityContext:
            runAsUser: 1000
```

Notice that this configuration is actually nested within a kapp controller App resource, and accompanied by a kapp Config resource.
kapp controller can ensure certain configuration in the Knative resource is immutable, as required by Knative (Cartographer cannot yet ensure this protection).

Don't worry about these nuances.
Rather, pay attention to the fact that the only Workload related configuration retained from the original Deployment and Service is the ContainerSpec portion of the Deployment.
The rest is configuration specific to the CI/CD tooling we want to leverage in this example.
In any case, all of this configuration needs to be done only once.

## Create the Supply Chain

Take a look at the [updated Supply Chain](example-2/ops/supply-chain.yaml).
Comparing it to the Supply Chain configuration from example 1, you should see that:
- The value of selector `app.tanzu.vmware.com/workload-type` is different, thus Workloads can specify one or the other
- The two resources for Deployment and Service have been replaced by a single one leveraging kapp controller and Knative

## Create Workload

Developers can reuse most of Workload configuration from example 1, with some exceptions:
- The label must match the new Supply Chain's selector
- Knative is more strict about syntax, so both `env` and `resources` fields must be specified, even if they are empty
- Knative is more strict about env var configuration, so some of the env vars in the `hello-knative` Workload cannot be used

Take a look at [example 2, nginx Workload](example-2/dev/workload-nginx-knative.yaml) and [example 2, hello-knative Workload](example-2/dev/workload-hello-knative.yaml).

## Deploy and test!

Deploy the templates and the Supply Chain.
Note that you need two of the templates from example 1, as well as the ops files from example 2.
There is no conflict between any of the config files, so you can also just deploy all of the ops files:
```shell
ytt -f example-1/ops -f example-2/ops | kapp deploy --yes -a example-supply-chain -f-
```

Check the status of the Supply Chain resources.
You should see `status: "True"` and `type: Ready`.
```shell
kapp inspect -a example-supply-chain --filter-name supplychain-web-image-knative --status
```

Deploy the Workload:
```shell 
kubectl apply -f example-2/dev/workload-hello-knative.yaml
```

Check the status of the Workload.
You should see `Status: "True"` and `Type: Ready`.
```shell
kubectl describe workload hello-knative
```

You can also list all resources of the expected types for this workflow.
```shell
kubectl get imagerepository,imagepolicy,app,all
```

The output should look as follows.
You will see the Deployment and Service created automatically by Knative, as well as some additional resources Knative creates.
```shell
$ kubectl get imagerepository,imagepolicy,app,all
NAME                                                    LAST SCAN              TAGS
imagerepository.image.toolkit.fluxcd.io/hello-knative   2021-11-29T06:17:12Z   14

NAME                                                LATESTIMAGE
imagepolicy.image.toolkit.fluxcd.io/hello-knative   paulbouwer/hello-kubernetes:1.10.1

NAME                                 DESCRIPTION           SINCE-DEPLOY   AGE
app.kappctrl.k14s.io/hello-knative   Reconcile succeeded   28s            5m51s

NAME                                                READY   STATUS    RESTARTS   AGE
pod/hello-knative-00001-deployment-b4fccc6f-v6888   2/2     Running   0          5m49s

NAME                                  TYPE           CLUSTER-IP     EXTERNAL-IP                         PORT(S)                                      AGE
service/hello-knative                 ExternalName   <none>         hello-knative.default.example.com   80/TCP                                       5m46s
service/hello-knative-00001           ClusterIP      10.96.144.45   <none>                              80/TCP                                       5m49s
service/hello-knative-00001-private   ClusterIP      10.96.203.72   <none>                              80/TCP,9090/TCP,9091/TCP,8022/TCP,8012/TCP   5m49s
service/kubernetes                    ClusterIP      10.96.0.1      <none>                              443/TCP                                      31h

NAME                                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/hello-knative-00001-deployment   1/1     1            1           5m49s

NAME                                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/hello-knative-00001-deployment-b4fccc6f   1         1         1       5m49s

NAME                                        URL                                        LATESTCREATED         LATESTREADY           READY     REASON
service.serving.knative.dev/hello-knative   http://hello-knative.default.example.com   hello-knative-00001   hello-knative-00001   Unknown   IngressNotConfigured

NAME                                      URL                                        READY     REASON
route.serving.knative.dev/hello-knative   http://hello-knative.default.example.com   Unknown   IngressNotConfigured

NAME                                              LATESTCREATED         LATESTREADY           READY   REASON
configuration.serving.knative.dev/hello-knative   hello-knative-00001   hello-knative-00001   True    

NAME                                               CONFIG NAME     K8S SERVICE NAME   GENERATION   READY   REASON   ACTUAL REPLICAS   DESIRED REPLICAS
revision.serving.knative.dev/hello-knative-00001   hello-knative                      1            True             1                 1
```

Notice also that since this Supply Chain uses kapp controller to create the Knative service, the Knative service resources can be queried using the `kapp` CLI.
Run the following commands:
```shell
# List Workload-related kapp apps
kapp list | grep ctrl
# Inspect resources, with status info
kapp inspect -a hello-knative-ctrl --status
```

> **Note:** You can ignore the warning "IngressNotConfigured."
> Indeed, we have not configured Ingress so this warning is expected.

If you want to test the app, start a port-forward process:
```shell
kubectl port-forward deployment/hello-knative-00001-deployment 8080:8080
```

Open `http://localhost:8080` in your browser or execute the following command in a separate terminal window. Either way you should see a "Welcome to nginx!" message.
```shell
curl http://localhost:8080
```

> Note:
>
> If you have any trouble, use `kubectl describe` to check the status of the ClusterSupplyChain, Workload, App, and Pod resources.
> Also, use `kubectl logs hello-knative-<pod-uuid> workload` or `stern hello-knative.*` to check the nginx Pod logs.

Use `Ctrl+C` to stop the port-forwarding process.

### Rinse and repeat!

Try deploying a second Workload using the same Supply Chain.
```shell 
kubectl apply -f example-2/dev/workload-nginx-knative.yaml
```

You can repeat the commands above, switching out hello-knative for nginx-knative, to track the success of the deployment.

## Cleanup

Delete the Workloads.
```shell
kubectl delete workload nginx-knative
kubectl delete workload hello-knative
```

Delete the Supply Chain configuration, including templates.
```shell
kapp delete --yes -a example-supply-chain
```

## Conclusion

With this example, you should see how Cartographer enables you to take advantage of myriad sophisticated CI/CD tools.
It also provides a clear separation of concerns between Developer and App Operator, enabling the operator to make changs to the pipeline without adding burden to developers.



[kapp controller]: https://carvel.dev/kapp-controller
[Knative serving]: https://knative.dev/docs/serving