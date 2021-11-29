# cartographer-demo

## Intro

[Cartographer] is a Kubernetes-native solution that enables you to stitch together a series of activities for continuous integration (CI) and continuous deployment (CD) of your applications. 
These secure and reusable sequences are called _Supply Chains_.

Supply Chains can specify any number of activities needed for CI/CD, such as testing code, building images, scanning artifacts, deploying resources, and triggering updates.
Cartographer choreographs a Supply Chain by monitoring the status of running activities and passing the output of one as input to the next.

The nitty-gritty of any given activity is carried out by a separate, specialized tool.
Cartographer provides a unified way to manage the configuration of these disparate CI/CD tools through a set of [custom resources], including cluster-wide Supply Chains and namespace-scoped application Workloads. 
In this way, Cartographer enables a clean separation of concerns between cluster tooling (platform operations), Supply Chain definition (app operations), and Workload configuration (development).

## What's in this repo?

This repo contains examples of Cartographer Supply Chains to deploy applications to Kubernetes. 
The examples provided begin with a very simple deployment workflow, and build up to a more robust path to production.

The CI/CD activities included in the examples depend on a selection of tools.
The charts below lists the activities for each example, the tool you will be using to accomplish that activity, and the resources you will need to configure (both the CI/CD tool resource, and the corresponding Cartographer resource).

#### Example 1 preview
Deploy an existing image with mininmal additional CI/CD tools.

| Activity | Tool | Tool Resource | Cartographer Resource |
| --- | --- | --- | --- |
| Detect image repo updates | Fluxcd | ImageRepository | ClusterSourceTemplate |
| Select new image tag | Fluxcd | ImagePolicy | ClusterImageTemplate |
| Run application | Kubernetes | Deployment | ClusterTemplate |
| Expose application| Kubernetes | Service | ClusterTemplate |

#### Example 2 preview
Leverage additional CI/CD tools to get source code, test it, build & publish an image, and deploy using supplemental deployment and runtime tooling.

| Activity | Tool | Tool Resource | Cartographer Resource |
| --- | --- | --- | --- |
| Detect source changes | Fluxcd | GitRepository | ClusterSourceTemplate |
| Test code | Tekton | Task | ClusterSourceTemplate, Runnable |
| Build & publish image | kpack | Image | ClusterImageTemplate |
| Deploy application | kapp controller | App, Config | ClusterTemplate |
| Run and expose application | Knative | Service | ClusterTemplate |

<hr />

Sound like a lot?!
Not to worry.
The following sections will guide you through all the necessary steps, including:
- Creating a local cluster and local image registry
- Installing Cartographer
- Installing additional required CI/CD tools
- Creating Supply Chains
- Deploying application Workloads

## Prerequisites

- [Carvel suite] (at minimum, `vendir`, `ytt`, and `kapp`)
- [kind], to create a local cluster
- Docker, to run the kind cluster and a local image registry
  
> **Note:**
> 
> This demo includes a script to start a local kind cluster and a local image registry.
> If you choose to use these, you can proceed to the next step.
> 
> If you prefer to use a different cluster and image registry, make sure that:
>  - You have admin access to the cluster
>  - The cluster is v1.19 or newer
>  - Your Kubernetes context is targeting your desired cluster
>  - You have push access to the image registry
>  - [values-overrides.yaml](values-overrides.yaml) is updated with your registry details and a sensible image_prefix value
 >   - Optional, but recommended: you can store your password in an environment variable called `YTT_registry__password` rather than in the file

## TL;DR Setup

To go through the cluster and CI/CD tool setup with some explanation, proceed to the next section.

To set up the cluster and CI/CD tooling in one shot and skip straight to the examples, run the following script.
> **Note:** if you are using your own cluster and registry, comment out the following line in the script:
> 
> `KIND_VERSION=v1.22.4 ./infra-cluster/kind-setup.sh`
```shell
# Create cluster, install & configure dependencies
./infra_install.sh
```

## Set up cluster and registry

To start a cluster and registry locally using docker, run the following commands:
```shell
# Start cluster and registry
vendir sync -d kind                         # Downloads kind-setup.sh script
KIND_VERSION=v1.22.4 ./infra-cluster/kind-setup.sh   # Creates cluster and registry
```

> _Credit for the above script goes to [Dave Syer](https://github.com/dsyer/kpack-with-kind) (thanks, Dave!)_

You can run the following commands to validate the cluster and registry are up and running:
```shell
# Check cluster - should return: "kind-control-plane"
kind get nodes
# Check registry - should return: "{}"
curl localhost:5000/v2/
```

## Install & configure CI/CD tools

Put on your Platform Operator hat and begin by installing a set of Kubernetes-native CI/CD tools capable of running specialized CI/CD activities. As per the table above, you will install:
- **_Fluxcd_**: to detect changes in a source repositories
- **_Tekton_**: for running tasks (e.g. testing the application)
- **_Kpack_**: for building and publishing container images
- **_Kapp Controller_**: for managing related sets of resources
- **_Knative_**: for facilitating serving of applications

You will also install **_Cartographer_** and an accompanying **_Cert Manager_**.

You can see the complete list of tools that will be installed by checking the [vendir.yml](vendir.yml) file, under `directories.path: infra-platform/base-vendir`.

#### Download installation files

Download all dependency installation files: 
```shell
# Download dependency files
vendir sync
```

You should see the following files on your machine:
```shell
$ tree infra-platform/base-vendir
infra-platform/base-vendir
├── cartographer
│   └── cartographer.yaml
├── cert-manager
│   └── cert-manager.yaml
├── flux2
│   └── install.yaml
├── kapp-controller
│   └── release.yml
├── knative-serving
│   ├── serving-core.yaml
│   └── serving-crds.yaml
├── kpack
│   └── release-0.4.2.yaml
└── tekton
    └── release.yaml
```

> **Note:**
> To use a newer version of any dependency, change the version in [vendir.yml](vendir.yml) and re-run `vendir sync`.

#### Review additional configuration files

The [infra-platform/base-creds](infra-platform/base-creds) directory contains configuration to create a Secret and ServiceAccount with push/pull access to the image registry.
Both kpack and kapp controller will use this ServiceAccount.

The [infra-platform/overlay](infra-platform/overlay) directory contains supplemental configuration.
In the case of kpack, it includes configuration to create a ClusterBuilder that can be used in all Supply Chains to build images ([infra-platform/overlay/kpack/kpack.yaml](infra-platform/overlay/kpack/kpack.yaml)).

#### Install dependencies

For convenience, a script is included to install all dependencies at once.
Run the following command, or open the script and copy one command at a time to your terminal to follow the progress at your own pace.
> **Note:** if you are using your own cluster and registry, comment out the following line in the script:
>
> `KIND_VERSION=v1.22.4 ./infra-cluster/kind-setup.sh`
```shell
# Install dependencies
./infra_install.sh
```

#### Validate installation

When the above command completes, you will have all the above tools installed in your cluster.
You can verify the installations by running the following command:
```shell
# Verify dependencies installation
kapp list
```

The output should look like this:
```
$ kapp list
Target cluster 'https://127.0.0.1:49461' (nodes: kind-control-plane)

Apps in namespace 'default'

Name             Namespaces                          Lcs   Lca  
cartographer     (cluster),cartographer-system       true  3m  
cert-manager     (cluster),cert-manager,kube-system  true  3m  
cicd-creds       default                             true  3m  
flux2            (cluster),flux-system               true  1m  
kapp-controller  (cluster),default,kapp-controller,  true  1m  
                 kube-system                                 
knative-serving  (cluster),knative-serving           true  1m  
kpack            (cluster),kpack                     true  1m  
tekton           (cluster),tekton-pipelines          true  1m  

Lcs: Last Change Successful
Lca: Last Change Age

8 apps

Succeeded
```

You can get more detail about any one of the applications using `kapp inspect...`
For example, run:
```shell
# Inspect a kapp-deployed application
kapp inspect -a cartographer
```

#### Validate kpack configuration

The kpack overlay configuration ([infra-platform/overlay/kpack/kpack.yaml](infra-platform/overlay/kpack)) instructed kpack to create and publish a [builder] to the image registry.
This builder can be used to build application images.

Verify that the builder is ready.
```shell
# Check status of builder resource
kubectl get clusterbuilder builder
```
The output should look something like this:
```
$ kubectl get clusterbuilder builder
NAME      LATESTIMAGE                                                                                                             READY
builder   registry.local:5000/cartographer-demo/builder@sha256:ceeebe78832f9d97e8f74b4585159198f57d9388e65f2319c59b544632b3ba87   True
````

Verify that the builder is in the image registry.
```shell
# Check image in registry
curl localhost:5000/v2/cartographer-demo/builder/tags/list
```

The output should look something like this:
```
$ curl localhost:5000/v2/cartographer-demo/builder/tags/list
{"name":"cartographer-demo/builder","tags":["20211123024750","latest"]}
```

<hr />

You now have the infrastructure in place to design the path to production for your applications.

> **Note:**
> 
> If you would like to learn more about the Carvel CLIs used in the [infra_install.sh](infra_install.sh) script (`vendir`, `ytt`, and `kapp`), check out [Carvel] or this [Carvel demo].

## Supply Chain examples

Now it's time to put on your Application Operator hat and think about the activities needed to deploy an application to Kubernetes.

#### Example 1: Continuous deployment

Beginning with a simple scenario, let's assume you are deploying 3rd party images, or you already have a process in place to publish images to a registry, and your goals are to:
- streamline CD, from new image detection to deployment
- use strictly core Kubernetes resources for runtime

To accomplish this without Cartographer, you would likely end up with a gitops repo per application, as well as tooling/scripting to update the git repo when new image tags are available, and tooling/scripting to poll the git repo and deploy the updated configuration to Kubernetes.

Cartographer simplifies this workflow by choreographing—in-cluster—the communication of information (e.g. new tag) between components, and by instantiating resources in the cluster (applying changes to Kubernetes resources).

Additionally, Cartographer enables you to template the configuration, so that it can be reused across Workloads.

##### Create templates

###### Polling the image repository

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

###### Choosing the tag

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

###### Applying Deployment and Service resources

Take a look at [example 1, Deployment template](example-1/ops/03-deployment-template.yaml).
You will notice a similar pattern.
This time, the Cartographer API is the generic _ClusterTemplate_, which does not have any output.
In this case it is wrapping the core Kubernetes Deployment API. 
Notice also the configuration of the Pod spec `container.image: $(images.image.image)$` within the Deployment.
This value refers to the output from the ImageRepository.
The precise syntax within the `$` signs should become clear in the next section, when you review the Supply Chain configuration.

Finally, you can review [example 1, Service template](example-1/ops/04-service-template.yaml).

##### Chain the templates together

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

##### Create Workload

Your Supply Chain can now be used for any number of application images.

###### What to tell developers

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

###### Configure the Workload

Time to put on your Developer hat!

As a developer, if you do not wish to change the value any of the optional or pre-set placeholders listed above, then a Workload configuration can be as simple as [example 1, nginx Workload](example-1/workload-nginx.yaml).

##### Deploy and test!

App operator hat back on, deploy the templates and the Supply Chain:
```shell
ytt -f example-1/ops | kapp deploy --yes -a example-1 -f-
```

Check the status of the Supply Chain resources.
You should see `status: "True"` and `type: Ready`.
```shell
kapp inspect -a example-1 --status
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

###### Rinse and repeat!

Try deploying a second Workload using the same Supply Chain.
```shell 
kubectl apply -f example-1/dev/workload-hello-k8s.yaml
```

You can repeat the commands above, switching out nginx for hello-k8s, to track the success of the deployment.

##### Cleanup

Delete the Workloads:
```shell
kubectl delete workload nginx
kubectl delete workload hello-k8s
```

Delete the Supply Chain configuration, including templates.
```shell
kapp delete --yes -a example-1
```

<hr />
Hopefully, with this example, you see the fundamental concepts behind Cartographer and can appreciate the power of choreographing myriad CI/CD tools in a reusable way.

#### Example 2: Continuous integration & simplified continuous deployment

Coming soon...

[Cartographer]: https://cartographer.sh
[Carvel suite]: https://carvel.dev/#whole-suite
[kind]: https://kind.sigs.k8s.io/docs/user/quick-start/#installation
[Carvel]: https://carvel.dev
[Carvel demo]: https://github.com/ciberkleid/carvel-demo
[kpack]: https://github.com/pivotal/kpack
[builder]: https://buildpacks.io/docs/concepts/components/builder
[stern]: https://github.com/wercker/stern
[custom resources]: https://cartographer.sh/docs/reference/#resources
[Workload API]: https://cartographer.sh/docs/reference/#workload
