# Example 1: Continuous deployment

Please make sure you have satisfied the prerequisites and setup as detailed in [README.md](README.md).

It's time to put on your Application Operator hat and think about the activities needed to deploy an application to Kubernetes.

Beginning with a simple scenario, let's assume you are deploying 3rd party images, or you already have a process in place to publish images to a registry, and you want to streamline CD, from new image detection to deployment.

To accomplish this without Cartographer, you would likely end up with a gitops repo per application with the configuration for a Kubernetes Deployment and Service resource. You'd also need tooling/scripting to poll for new images and update the Deployment config, and tooling/scripting to poll the gitops repo and apply changes to Kubernetes.

Cartographer simplifies this workflow by choreographing—in-cluster—the communication of information (e.g. new tag) between components, and by instantiating resources in the cluster (applying changes to Kubernetes resources).

Additionally, Cartographer enables you to template the configuration, so that it can be reused across Workloads.

## Create templates

### Polling the image repository

To poll an image repository, you can use Fluxcd's ImageRepository resource.

Using only Fluxcd, your configuration might look like this:
```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageRepository
metadata:
  name: nginx
  labels:
    app.kubernetes.io/part-of: nginx
spec:
  image: nginx
  interval:  3m
```

Cartographer requires that you wrap your Kubernetes configuration with a CartographerAPI.
ImageRepository polls the source location, acting as the trigger for a deployment, so you would use the Cartographer _ClusterSourceTemplate_ API.

To make the configuration reusable across different Workloads, you would also template the app-specific values.

Using Cartographer, your configuration might look like this instead:
```yaml
---
apiVersion: carto.run/v1alpha1
kind: ClusterSourceTemplate
metadata:
  name: image-repository
spec:
  urlPath: .status.canonicalImageName
  revisionPath: .status.canonicalImageName
  template:
    apiVersion: image.toolkit.fluxcd.io/v1beta1
    kind: ImageRepository
    metadata:
      name: $(workload.metadata.name)$
      labels:
        app.kubernetes.io/part-of: $(workload.metadata.name)$
    spec:
      image: $(workload.spec.image)$
      interval:  3m
```

Notice:
- the top-level ClusterSourceTemplate resource, with the ImageRepository configuration embedded under the generic `spec.template` node
- the templated values that will be obtained from an app-specific Workload resource: `$(workload.<yaml path>)$`
- the fields to capture the output of ImageRepository from its `.status` information

When a developer submits a Workload, Cartographer will instantiate the ImageRepository resource.
Whenever the status of this resource changes, Cartographer can pass the output to another resource for processing.

### Choosing the tag

To select a new tag for deployment, you can use Fluxcd's ImagePolicy resource. An ImagePolicy resource receives the tag list from ImageRepository and selects one based on your desired policy (e.g. alphabetical, semver, etc).

The output of an ImagePolicy resource is the new image tag, and so it corresponds to the Cartographer _ClusterImageTemplate_ API.

The configuration might look like this:
```yaml 
apiVersion: carto.run/v1alpha1
kind: ClusterImageTemplate
metadata:
  name: image-policy
spec:
  imagePath: .status.latestImage
  params:
    - name: semver
      default: '>=1.0.0'
  template:
    apiVersion: image.toolkit.fluxcd.io/v1beta1
    kind: ImagePolicy
    metadata:
      name: $(workload.metadata.name)$
      labels:
        app.kubernetes.io/part-of: $(workload.metadata.name)$
    spec:
      imageRepositoryRef:
        name: $(workload.metadata.name)$
      policy:
        semver:
          range: $(params.semver)$
```

Notice:
- the top-level ClusterImageTemplate resource, with the ImagePolicy configuration embedded under the generic `spec.template` node
- the templated values that will be obtained from an app-specific Workload resource: `$(workload.<yaml path>)$`
- additional templating using optional custom parameters with default values
- the field to capture the output of ImagePolicy from its `.status` information

> **Note:**
>
> You might be wondering why you don't see any configuration to pass the output from ImageRepository to any field in the ImagePolicy spec?
> This is because ImageRepository and ImagePolicy are both Fluxcd resources designed to work together (notice the `imageRepositoryRef` configuration).
> Hence, in this particular case, there is no need for Cartographer to feed ImagePolicy with any output from ImageRepository.

Cartographer will monitor the status of the ImagePolicy resource and capture the output from the status details, as defined above: `spec.imagePath: .status.latestImage`.
Next, we want Cartographer to interpolate this information into the Deployment resource configuration and create the Deployment and Service resources.

### Applying Deployment and Service resources

Take a look at [example 1, Deployment template](example-1/ops/03-deployment-template.yaml).
You will notice a similar pattern.
This time, the Cartographer API is the generic _ClusterTemplate_, which does not have any output.
In this case it is wrapping the core Kubernetes Deployment API.
Notice also the configuration of the Pod spec `container.image: $(images.image.image)$` within the Deployment.
This value refers to the output from the ImageRepository.
The precise syntax within the `$` signs should become clear in the next section, when you review the Supply Chain configuration.

Finally, you can review [example 1, Service template](example-1/ops/04-service-template.yaml).

## Chain the templates together

At this point, you have the necessary templates to design the continuous deployment workflow for your images.
You need to "stitch" the templates together into a sequential _Supply Chain_.
You do this using the Cartographer _ClusterSupplyChain_ API.

Take a look at [example 1, Supply Chain config](example-1/ops/supply-chain.yaml).

Notice the following:
- ClusterSupplyChain includes a selector: `spec.selector: app.tanzu.vmware.com/workload-type`.
    - This selector is the key to associating developer Workloads with Supply Chains.
      Any developer Workload that contains the same value will be handled by this Supply Chain
-  The four templates you reviewed in the last section are listed as resources, in order
- The Supply Chain can be used to overwrite the templates' default `params` values
- The outputs from _ClusterSourceTemplate_ and _ClusterImageTemplate_ are configured as inputs to the subsequent template in the chain, as highlighted below:
    - For the ImagePolicy, which depends on ImageRepository status updates:
       ```yaml 
       sources:
         - resource: source-provider
           name: source
       ```
    - For the Deployment, which depends on ImagePolicy status updates:
       ```yaml 
       images:
         - resource: image-builder
           name: image
       ```   
Recall the image template path used in the Pod spec in [example 1, Deployment template](example-1/ops/03-deployment-template.yaml): `image: $(images.image.image)$`.
This path derives from the above configuration. You can use `$(images.<name>.image)` or, since there is only one input of type images, you could simply use `$(image)$` as well.

## Create Workload

Your Supply Chain can now be used for any number of application images.

### What to tell developers

As an app operator, you need only provide developers with the set of parameters you need from them.

To use this Supply Chain, developers need to submit Cartographer _Workload_ configs that include:
- a label matching the Supply Chain's `app.tanzu.vmware.com/workload-type` selector
- values for placeholders that begin with `workload` or `params`

Specifically, for this example, the placeholders used are:

| Placeholer | Value |
| --- | --- |
| `$(workload.metadata.name)$` | required |
| `$(workload.spec.image)$` | required |
| `$(workload.spec.env)$` | optional (for Deployment) |
| `$(workload.spec.resources)$` | optional (for Deployment) |
| `$(params.semver)$ ` | set to: '>=1.0.0' |
| `$(params.containerPort)$` | set to: 80 |

And the value of `app.tanzu.vmware.com/workload-type` is `web-image`.

### Configure the Workload

Time to put on your Developer hat!

As a developer, if you do not wish to change the value any of the optional or pre-set placeholders listed above, then a Workload configuration can be as simple as [example 1, nginx Workload](example-1/workload-nginx.yaml).

## Deploy and test!

App operator hat back on, deploy the templates and the Supply Chain:
```shell
ytt -f example-1/ops | kapp deploy --yes -a example-supply-chain -f-
```

Check the status of the Supply Chain resources.
You should see `status: "True"` and `type: Ready`.
```shell
kapp inspect -a example-supply-chain --status
```

Switch again to your developer hat and deploy the Workload:
```shell 
kubectl apply -f example-1/dev/workload-nginx.yaml
```

Check the status of the Workload.
You should see `Status: "True"` and `Type: Ready`.
```shell
kubectl describe workload nginx
```

You can also list all resources of the expected types for this workflow:
```shell
kubectl get imagerepository,imagepolicy,all
```

The output should look like this:
```shell
$ kubectl get imagerepository,imagepolicy,all
NAME                                                       LAST SCAN              TAGS
imagerepository.image.toolkit.fluxcd.io/nginx   2021-11-27T19:35:00Z   377

NAME                                                   LATESTIMAGE
imagepolicy.image.toolkit.fluxcd.io/nginx   nginx:1.21.4

NAME                                    READY   STATUS    RESTARTS   AGE
pod/nginx-587c77997d-vrltq   1/1     Running   0          39s

NAME                       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/kubernetes         ClusterIP   10.96.0.1       <none>        443/TCP   2d21h
service/nginx   ClusterIP   10.96.111.176   <none>        80/TCP    39s

NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx   1/1     1            1           39s

NAME                                          DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-587c77997d   1         1         1       39s
```

If you want to test the app, start a port-forward process:
```shell
kubectl port-forward service/nginx 8080:80
```

Open `http://localhost:8080` in your browser or execute the following command in a separate terminal window. Either way you should see a "Welcome to nginx!" message.
```shell
curl http://localhost:8080
```

> Note:
>
> If you have any trouble, use `kubectl describe` to check the status of the ClusterSupplyChain, Workload, and Pod resources.
> Also, use `kubectl logs nginx-<pod-uuid>` or `stern nginx.*` to check the nginx Pod logs.

Use `Ctrl+C` to stop the port-forwarding process.

### Rinse and repeat!

Try deploying a second Workload using the same Supply Chain.
```shell 
kubectl apply -f example-1/dev/workload-hello-k8s.yaml
```

You can repeat the commands above, switching out nginx for hello-k8s, to track the success of the deployment.

## Cleanup

Delete the Workloads:
```shell
kubectl delete workload nginx
kubectl delete workload hello-k8s
```

Delete the Supply Chain configuration, including templates.
```shell
kapp delete --yes -a example-supply-chain
```

## Conclusion

Hopefully, with this example, you see the fundamental concepts behind Cartographer and can appreciate the power of choreographing myriad CI/CD tools in a reusable way.
