# cartographer-demo

## Intro

[Cartographer] is a Kubernetes-native solution that enables you to stitch together a series of activities for continuous integration (CI) and continuous deployment (CD) of your applications. 
These secure and reusable sequences are called _supply chains_.

Supply chains can specify any number of activities needed for CI/CD, such as testing code, building images, scanning artifacts, deploying resources, and triggering updates.
Cartographer choreographs a supply chain by monitoring the status of running activities and passing the output of one as input to trigger the next.

The nitty-gritty of any given activity is carried out by a separate, specialized tool.
Cartographer provides a unified way to manage the configuration of these disparate CI/CD tools through a set of [custom resources], including cluster-wide supply chains and namespace-scoped application workloads. 
In this way, Cartographer enables a clean separation of concerns between cluster tooling (platform ops), supply chain definition (app ops, or devops), and workload configuration (dev).

## What's in this repo?

This repo contains examples of Cartographer supply chains to deploy applications to Kubernetes. 
The examples provided begin with a very simple deployment workflow, and build up to a more robust path to production.

The CI/CD activities included in the examples depend on a selection of tools.
The chart below lists the activities, the tool you will be using to accomplish that activity, and the Kubernetes resources you will need to configure (both the CI/CD tool resource, and the corresponding Cartographer resource).

| Activity | Tool | Tool Resource | Cartographer Resource |
| --- | --- | --- | --- |
| Detect source changes | fluxcd source controller | GitRepository | ClusterSourceTemplate |
| Test code | tekton | Task | ClusterSourceTemplate, Runnable |
| Build & publish image | kpack | Image | ClusterImageTemplate |
| Run application (option 1) | kubernetes | Deployment | ClusterTemplate |
| Expose application (option 1) | kubernetes | Service | ClusterTemplate |
| Deploy application (option 2) | kapp controller | App, Config | ClusterTemplate |
| Run and expose application (option 2) | knative | Service | ClusterTemplate |

Sound like a lot?!
Not to worry.
The following sections will guide you through all the necessary steps, including:
- Creating a local cluster and local image registry
- Installing Cartographer
- Installing additional required CI/CD tools
- Creating supply chains
- Deploying application workloads

## Prerequisites

- [Carvel suite] (at minimum, `vendir`, `ytt`, and `kapp`)
- [kind], to create a local cluster
- Docker, to run the kind cluster and a local image registry
  
> **Note**
> 
> This demo includes a script to start a local kind cluster and a local image registry.
> If you choose to use these, you can proceed to the next step.
> 
> If you prefer to use a different cluster and image registry, make sure that:
>  - You have admin access to the cluster
>  - The cluster is v1.19 or newer
>  - Your kubernetes context is targeting your desired cluster
>  - You have push access to the image registry
>  - [values-overrides.yaml](values-overrides.yaml) is updated with your registry details and a sensible imagePrefix value
 >   - Optional, but recommended: you can store your password in an environment variable called `YTT_registry__password` rather than in the file

## TL;DR Setup

To go through the cluster and CI/CD tool setup with some explanation, proceed to the next section.

To set up the cluster and CI/CD tooling in one shot and skip straight to the examples, run the following script.
> Note: if you are using your own cluster and registry, comment out the following line in the script:
> 
> `KIND_VERSION=v1.22.4 ./kind/kind-setup.sh`
```shell
# Create cluster, install & configure dependencies
./infra_install.sh
```

## Set up cluster and registry

To start a cluster and registry locally using docker, run the following commands:
```shell
# Start cluster and registry
vendir sync -d kind                         # Downloads kind-setup.sh script
KIND_VERSION=v1.22.4 ./kind/kind-setup.sh   # Creates cluster and registry
```

You can run the following commands to validate that the cluster and registry are up and running:
```shell
# Check cluster and registry
kind get nodes            # should return: "kind-control-plane"
curl localhost:5000/v2/   # should return: "{}"
```

> Credit for the above script goes to [Dave Syer](https://github.com/dsyer/kpack-with-kind) (thanks, Dave!)

## Install & configure CI/CD tools

Put on your Platform Operator hat and begin by installing a set of Kubernetes-native CI/CD tools capable of running specialized CI/CD activities. As per the table above, you will install:
- **_Fluxcd Source Controller_**: to detect changes in a git repository
- **_Tekton_**: for running tasks (e.g. testing the application)
- **_Kpack_**: for building and publishing container images
- **_Kapp Controller_**: for managing related sets of resources
- **_Knative_**: for facilitating serving of applications

You will also install **_Cartographer_** and an accompanying **_Cert Manager_**.

You can see the complete list of tools that will be installed by checking the [vendir.yml](vendir.yml) file, under `directories.path: infra/base-vendir`.

#### Download installation files

Download all dependency installation files: 
```shell
# Download dependency files
vendir sync
```

You should see the following files on your machine:
```shell
$ tree infra/base-vendir
infra/base-vendir
├── cartographer
│   └── cartographer.yaml
├── cert-manager
│   └── cert-manager.yaml
├── gitops-toolkit
│   ├── source-controller.crds.yaml
│   └── source-controller.deployment.yaml
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

The [infra/base-creds](infra/base-creds) directory contains configuration to create a Secret and ServiceAccount with push/pull access to the image registry.
Both kpack and kapp controller will use this ServiceAccount.

The [infra/overlay](infra/overlay) directory contains supplemental configuration, mostly namespace, role, and rolebinding resources.
In the case of kpack, it also contains configuration to create a ClusterBuilder that can be used in all supply chains to build images ([infra/overlay/kpack/kpack.yaml](infra/overlay/kpack/kpack.yaml)).

#### Install dependencies

For convenience, a script is included to install all dependencies at once.
Run the following command, or open the script and copy one command at a time to your terminal to follow the progress at your own pace.
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

You can get more detail about any one of the applications using `kapp inspect...`
For example, run:
```shell
# Inspect a kapp-deployed application
kapp inspect -a cartographer
```

#### Validate kpack configuration

The kpack overlay configuration ([infra/overlay/kpack/kpack.yaml](infra/overlay/kpack)) instructed kpack to create and publish a [builder] to the image registry.
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

## Supply Chain Examples

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
