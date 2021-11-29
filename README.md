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

## Platform setup

To go through the cluster and CI/CD tool setup with some explanation, see [README-infra.md](README-infra.md).

To set up the cluster and CI/CD tooling in one shot and skip straight to the examples, run the following script.
> **Note:** if you are using your own cluster and registry, comment out the following line in the script:
>
> `KIND_VERSION=v1.22.4 ./infra-cluster/kind-setup.sh`
```shell
# Create cluster, install & configure dependencies
./infra_install.sh
```

## Supply Chain examples

#### Example 1: Continuous deployment

[Example 1 README](README-example-1.md)

#### Example 2: Continuous integration & simplified continuous deployment

[Example 2 README](README-example-2.md)





[Cartographer]: https://cartographer.sh
[custom resources]: https://cartographer.sh/docs/reference/#resources
[Carvel suite]: https://carvel.dev/#whole-suite
[kind]: https://kind.sigs.k8s.io/docs/user/quick-start/#installation
