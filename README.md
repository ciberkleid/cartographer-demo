# cartographer-demo

## Intro

[Cartographer] is a Kubernetes-native solution that enables you to stitch together a series of activities for continuous integration (CI) and continuous deployment (CD) of your applications. These secure and reusable sequences are called _supply chains_.

Supply chains can specify any number of activities needed for CI/CD, such as testing code, building images, scanning artifacts, deploying resources, and triggering updates.
Each activity must be carried out by a separate, specialized tool.
Cartographer choreographs a supply chain by configuring the individual activities using your choice of CI/CD tools and passing the output of one as input to another.

By providing thoughtfully designed supply chain configuration APIs, Cartographer provides a unified and reusable way to manage the configuration of disparate CI/CD tools, and it enables a clean separation of concerns between cluster tooling (platform ops), supply chain definition (devops), and workload configuration (dev).

## What's in this repo?

This repo contains demos of Cartographer supply chains to deploy a hello-world demo application to Kubernetes.
1. Simple supply chain that leverages:
    - `kpack` to build and publish the image
    - `kube API` to deploy
2. More comprehensive supply chain that leverages:
   - `source-resolver` to detect code commits
   - `tekton` to test the app
   - `kpack` to build and publish the image
   - `kapp controller` to deploy
   - `knative` to serve the app

## Prerequisites

- [Carvel suite] installed locally (at minimum, `vendir`, `ytt`, and `kapp` are required)
- Docker installed locally
- Access to a Kubernetes cluster (see below to use `kind`)
- Access to an image registry (see below to use a local registry)

#### Download dependency files
All dependencies are specified in the file [vendir.yml](vendir.yml).
Feel free to peruse this file.

Download all dependency files: 
```shell
# Download dependency files
vendir sync
```

> **Note:**
> 
> To use a newer version of any dependency, change the version in [vendir.yml](vendir.yml) and re-run `vendir sync`.

#### Create cluster and registry

To start a kind cluster with a local image registry, run the following command.
```shell
# Start cluster and registry
KIND_VERSION=v1.22.4 ./kind/kind-setup.sh
```
This starts a Kubernetes cluster and an image registry, both running in Docker on your local machine. The image registry is listening on `localhost:5000`.

> Credit for the above script goes to [Dave Syer](https://github.com/dsyer/kpack-with-kind) (thanks, Dave!)

## Install & configure dependencies

Put on your Platform Operator hat and begin by installing a set of Kubernetes-native CI/CD tools capable of running specialized CI/CD activities. Specifically, you will install:
- **_Fluxcd Source Controller_**: to detect changes in a git repository
- **_Tekton_**: for running tasks (e.g. testing the application)
- **_Kpack_**: for building an publishing container images
- **_Kapp Controller_**: for managing related sets of resources
- **_Knative_**: for facilitating serving of applications

You will also install **_cartographer_** and an accompanying **_cert-manager_**.

You can see the complete list of tools that will be installed by checking the [vendir.yml](vendir.yml) file (under `directories.path: infra/base-vendir`).

#### Create shared secret and service account

A couple of these tools (specifically, _kpack_ and _kapp controller_) require access to push and/or pull images from the image registry.

Create a Secret and ServiceAccount for these tools to use:
```shell
# Create common secret and service account for registry push/pull access
ytt -f infra/base-creds | kapp deploy --yes -a cicd-creds -f-
```

> **Note:**
> 
> If you are not using the local registry, you need to provide your on credentials hen creating the Secret.
> To do so, edit the file [values-overrides.yaml](values-overrides.yaml) to specify your registry details.
> To avoid the risk of exposing your password or access token, use environment variable _YTT_registry__password_ to specify your password.
> Add these as arguments to the command above:
> 
> `ytt -f infra/base-creds --data-values-file values-overrides.yaml --data-values-env YTT | kapp ...`

#### Install dependencies

Install all depenencies.

For convenience, a script is provided.
Run the following command, or open the script and copy one command at a time to your terminal to follow the results at your own pace.
```shell
# Install dependencies
./infra_install.sh
```

When this command completes, you will have all of the above tools installed in your cluster.
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
gitops-toolkit   (cluster),gitops-toolkit            true  1m  
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

You can get more detail about any one of the tools installed using `kapp insepct...`
For example, run:
```shell
# Inspect a kapp-deployed application
kapp inspect -a cartographer
```

Notice that the `kpack` configuration included the creation of a builder capable of building images for several types of applications. You can see the configuration in [infra/overlay/kpack/kpack.yaml](infra/overlay/kpack).
This configuration instructs kpack to build an image and publish it to the container registry, so it can be used to build applications.
You can verify that the image is ready and that it is available in the registry by running the following commands.
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

You can also verify the image was published to the registry.
```shell
# Check image in registry
curl localhost:5000/v2/cartographer-demo/builder/tags/list
```

The output should look something like this:
```
$ curl localhost:5000/v2/cartographer-demo/builder/tags/list
{"name":"cartographer-demo/builder","tags":["20211123024750","latest"]}
```

You now have the infrastructure in place to design the path to production for your applications.

> **Note:**
> 
> If you would like to learn more about the Carvel CLIs used in the [infra_install.sh](infra_install.sh) script (`vendir`, `ytt`, and `kapp`), check out [Carvel] or this [Carvel demo].

## Examples

### Example 1

#### DevOps: Create the supply chain

Now it's time to put on your DevOps hat and think about the activities needed to deploy an application to Kubernetes.

At minimum, you need to build a container image, store the image in a registry, and create Deployment and Service resources in Kubernetes.

If you were doing this manually, you could accomplish this by creating:
- a `kpack` Image resource (polls git, builds & publishes image)
- a Deployment resource
- a Service resource

Rather than have development teams create these three resources for each application, Cartographer enables you to define these once as templates, so that developers need only specify the value(s) uniue to their applications.
Cartographer will then interpolate the values and create resources for each application.

In addition, even if you were to create the necessary resources, you would still need a mechanism to trigger the deployment when a new image is ready.
Here again Cartographer can fill the gap, passing the output from the `kpack` Image to the Deployment.

###### Template supply chain activities

Examine the template for the `kpack` Image.
```shell
cat examples/example-1/01-devops/image-template.yaml
```

Notice the resource type (`kind: ClusterImageTemplate`).
This resource is an abstraction provided by cartographer.
Notice also that it embeds a kpack Image resource type.
You could choose a different mechanism for building images by embedding a different resource within the ClusterImageTemplate.

Finally, notice that certain inputs are templated (e.g. `$(workload.metadata.name)$`).
This is evidence of the choreography that cartographer enables by passing outputs of one cartographer resource as inputs to another.
In this case, cartographer is passing outputs of a Workload resource, which will be defined by a developer for a specific application, to the Image template.

Examine the Deployment and Service templates and notice the same characteristics.
```shell
cat examples/example-1/01-devops/deployment-template.yaml
cat examples/example-1/01-devops/service-template.yaml
```

In this case, notice that the top-level cartographer resource is `kind: ClusterTemplate`.
Notice also that the output of the ClusterImageTemplate is passed to the Deployment container image tag (`image: $(images.image.image)$`).


Create the supply chain.
```shell
ytt -f examples/example-1/01-devops | kapp deploy --yes -a supply-chain-1 -f-
```

###### Compose supply chain from templates

Now that you have reusable templates defined for each activity, you can compose them into a supply chain.

Examine the template for the `kpack` Image.
```shell
cat examples/example-1/01-devops/_supply-chain.yaml
```

Notice the top-level cartographer resource ().
Notice also the mapping of the image output as an input to the deployment.
_Hint:_ look for the following lines in the file:
```
      images:
        - resource: image-builder
          name: image
```

#### Developer: Deploy an application

Now put on your Developer hat: it's time to deploy an application.

Cartographer provides a Workload resource to enable developers to provide the configuration that is unique to an application.
This configuration serves as input to the supply chain templates.

Examine a workload for a simple Go application:
```shell
cat examples/example-1/02-developer/workload-go.yaml
```
Notice the workload `metadata.labels.app.tanzu.vmware.com/workload-type` matches the `spec.selector.app.tanzu.vmware.com/workload-type` of the supply chain.
This enables cartographer to match the workload to the supply chain.

Apply the workload to the cluster.
```shell
kubectl apply -f examples/example-1/02-developer/workload-go.yaml
```

Track the progress using [stern].
You should see logging from two pods:
   - kpack's build pod, where the app image is built
   - the app pod, once the deployment has been created
> **Note:** Use `Ctrl+C` to quit stern when you see the logging from the workload container in the application pod.
```shell
# Tail the pod logs
stern hello-golang
```

You can also explicitly check for the resources created by the supply chain:
```shell
kubectl get workload,gitrepo,image,build,deploy,pod,service
```

You can also test the application.
In one terminal winow, run:
```shell
kubectl port-forward svc/hello-golang 8080:80
```

In a another terminal window, run:
```shell
curl localhost:8080
```

You should receive a `Hello World!` response to the request.

You can quit the port-forward process using `Ctrl+C`.

Delete the workload and the supply chain.
```shell
kubectl delete workload hello-golang
kapp delete --yes -a supply-chain-1
```

### Example 2 

Coming soon...




[Cartographer]: https://cartographer.sh
[Carvel suite]: https://carvel.dev/#whole-suite
[Carvel]: https://carvel.dev
[Carvel demo]: https://github.com/ciberkleid/carvel-demo
[kpack]: https://github.com/pivotal/kpack
[stern]: https://github.com/wercker/stern