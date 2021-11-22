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
ytt -f infra/base-common | kapp deploy --yes -a cicd-creds -f-
```

> **Note:**
> 
> If you are not using the local registry, you need to provide your on credentials hen creating the Secret.
> To do so, edit the file [values-overrides.yaml](values-overrides.yaml) to specify your registry details.
> To avoid the risk of exposing your password or access token, use environment variable _YTT_registry__password_ to specify your password.
> Add these as arguments to the command above:
> 
> `ytt -f infra/base-common --data-values-file values-overrides.yaml --data-values-env YTT | kapp ...`

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

> **Note:**
> 
> If you would like to learn more about the Carvel CLIs used in the [infra_install.sh](infra_install.sh) script (`vendir`, `ytt`, and `kapp`), check out [Carvel] or this [Carvel demo].

## Examples

### Example 1


At minimum, to deploy an application to Kubernetes you need to build a container image, store the image in a registry that Kubernetes can access, and create a deployment and service in Kubernetes.

In this example you will review and run a supply chain that orchestrates these basic activities.

To build the container image in this example, we will use [kpack].

Ideally




To create Deployment and Service resources for our app, will manually create the necessary resources and have them applied to the cluster.


### Example 2 

Coming soon...




[Cartographer]: https://cartographer.sh
[Carvel suite]: https://carvel.dev/#whole-suite
[Carvel]: https://carvel.dev
[Carvel demo]: https://github.com/ciberkleid/carvel-demo
[kpack]: https://github.com/pivotal/kpack