## Cartographer demo

## Contents
- [Intro](README.md/#Intro)
- [What's in this repo?](README.md/#Whats-in-this-repo?)
- [Setup](README.md/#Setup)
- [Cartographer Fundamentals and Syntax](README.md/#Cartographer-Fundamentals-and-Syntax)
- [Continuous Integration and Deployment with ClusterSupplyChains](README.md/#Continuous-Integration-and-Deployment-with-ClusterSupplyChains)
- [Continuous Integration and Delivery with ClusterSupplyChains and ClusterDeliveries](README.md/#Continuous-Integration-and-Delivery-with-ClusterSupplyChains-and-ClusterDeliveries)
- [Cleanup](README.md/#Cleanup)

## Intro

[Cartographer] is a Kubernetes-native solution that enables you to stitch together the necessary activities for continuous integration, deployment, and delivery (CI/CD) of your applications.
This can include testing code, building images, scanning artifacts, generating declarative configuration, deploying resources, or any other objective to meet your needs.

The nitty-gritty of any given activity is carried out by a separate, specialized tool (e.g. Flux, Tekton, kpack, and/or others).
Cartographer eases the burden of managing and integrating these disparate tools by providing a layer of abstraction for composing secure and reusable workflows called _Supply Chains_ and _Deliveries_.
Developers can then leverage these reusable workflows for specific applications using _Workloads_ and _Deliverables_.

In this way, Cartographer facilitates a separation of concerns between cluster tooling and CI/CD workflow definition (platform and application operations, respectively), and application onboarding/configuration (application development).
Cartographer also choreographs the execution of the workflows for each application by continuously monitoring the status of running activities and passing the output of one as input to the next.

## What's in this repo?

This repo contains example Supply Chains and Deliveries that you can use as a resource for learning Cartographer, or as a starting point for creating your own workflows.

Supply Chains enable you to automate the process of generating deployment-ready artifacts from source.
These artifacts are typically:
- a container image built from the application source code
- accompanying yaml configuration for deployment to Kubernetes

As a developer iterating over your own source code, you may want to simply generate a container image and apply yaml coniguration to the same cluster in which you are running the Supply Chain.
Example [dev-sandbox](./examples/dev-sandbox) covers this use case.

As a developer preparing an application for deployment to different clusters, or for deployment at a later point in time, you may want to publish the yaml to some persistent storage external to the cluster.
Examples [e2e-gitops](./examples/e2e-gitops) and [e2e-pkgops](./examples/e2e-pkgops) cover this use case, using either git or an image repository as the external store for ops configuration.
For this use case, you will leverage a Delivery in addition to a Supply Chain.

The examples leverage the following tools:

- **_Fluxcd_**: to poll source repositories for updates
- **_Kpack_**: for building and publishing container images
- **_Tekton_**: for running custom tasks (e.g. testing code, persisting declarative config)
- **_Knative Serving_**: for facilitating deployment and serving of applications
- **_Carvel Tool Suite_**: for packaging declarative config as an image and for managing related sets of resources

Don't worry; you don't need to be familiar with these tools ahead of time.
These examples will show how Cartographer helps you leverage them more easily and all together.
Thus, you can use this demo as a starting point for familiarizing yourself with these tools as well.

## Setup

Please follow the instructions in [README-setup.md](./README-setup.md) to create a cluster and set up the prerequisites required for the examples.

When you have completed the setup, return here to continue with the rest of the demo.

## Cartographer Fundamentals and Syntax

Please read through [README-carto101.md](./README-carto101.md) to learn fundamentals and syntax for configuring Cartographer.

When you are done, return here to continue with the rest of the demo.

## Continuous Integration and Deployment with ClusterSupplyChains

#### Example: Developer Sandbox, Supply Chain 1

Please follow [dev-sandbox README-1.md](./examples/dev-sandbox/README-1.md) for instructions on running the following scenario:

| Activity | Tool | Tool Resource |
| --- | --- | --- |
| Detect changes to git source repo | Flux | GitRepository |
| Build & publish image | kpack | Image |
| Run application | Kubernetes | Deployment |
| Expose application| Kubernetes | Service |

#### Example: Developer Sandbox, Supply Chain 2

Please follow [dev-sandbox README-2.md](./examples/dev-sandbox/README-2.md) for instructions on running the following scenario:

| Activity | Tool | Tool Resource |
| --- | --- | --- |
| Detect changes to git source repo | Flux | GitRepository |
| Test source code | Tekton | TaskRun |
| Build & publish image | kpack | Image |
| Apply configuration | Kapp | App |
| Run and expose application| Knative | Service |

## Continuous Integration and Delivery with ClusterSupplyChains and ClusterDeliveries

#### Example: End-to-end GitOps, Supply Chain and Delivery

Please follow [e2e-gitops README.md](./examples/e2e-gitops/README.md) for instructions on running the following scenario:

**For the Supply Chain:**

| Activity | Tool | Tool Resource |
| --- | --- | --- |
| Detect changes to git source repo | Flux | GitRepository |
| Test source code | Tekton | TaskRun |
| Build & publish image | kpack | Image |
| Generate configuration for Knative Service | Kubernetes | ConfigMap |
| Export configuration to git | Tekton | TaskRun |

**For the Delivery:**

| Activity | Tool | Tool Resource |
| --- | --- | --- |
| Detect changes to git ops repo | Flux | GitRepository |
| Apply configuration | Kapp | App |
| Run and expose application| Knative | Service |

#### Example: End-to-end "ImgpkgOps", Supply Chain and Delivery

Please follow [e2e-pkgops README.md](./examples/pkg-gitops/README.md) for instructions on running the following scenario:

**For the Supply Chain:**

| Activity | Tool | Tool Resource |
| --- | --- | --- |
| Detect changes to git source repo | Flux | GitRepository |
| Test source code | Tekton | TaskRun |
| Build & publish image | kpack | Image |
| Generate configuration for Knative Service | Kubernetes | ConfigMap |
| Export configuration for Knative Service to image registry | Tekton | TaskRun |
| Export configuration for Package to image registry | Tekton | TaskRun |

**For the Delivery:**

| Activity | Tool | Tool Resource |
| --- | --- | --- |
| Detect changes to package image | Flux | ImageRepository, ImagePolicy |
| Apply configuration | Kapp | App, PackageRepository |
| Install Package | Kapp | App, PackageInstall |
| Run and expose application| Knative | Service |

## Cleanup

If you created a `kind` cluster during the setup, you can delete the whole cluster:
```shell
kind delete cluster --name cartographer-demo
```

If you provided your own cluster and want to do a more selective cleanup:

**1. Delete Workloads and Deliverables**

List the workloads and deliverables using `kubectl get workloads,deliverables -A`, and then use `kubect delete <type> <name> -n <namespace>` to delete each one.
This will also delete the associated resources and the app.

**2. Delete ClusterSupplyChains and ClusterDeliveries**

Run `kapp delete -a example-workflows -n default --yes`

**3. Delete tools**

List the applications using `kapp list -A`, and then use `kapp delete -a <application name> -n <namespace>` to delete each one.

**4. Delete images**

If you are using Google Artifact Repository, go to your GCP Console and delete the images created by the demo to avoid incurring any storage cost.

[Cartographer]: https://cartographer.sh