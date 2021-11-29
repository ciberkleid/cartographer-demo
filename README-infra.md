# Platform setup

This guide will walk through the setup of a local cluster using kind, a local image registry, and the installation of the CI/CD tooling required for the examples.

Before proceeding, make sure you have satisfied the prerequisites in [README.md](README.md).

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

Put on your Platform Operator hat and begin by installing a set of Kubernetes-native CI/CD tools capable of running specialized CI/CD activities. As reuired by the examples, you will install:
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

## Conclusion

You now have the infrastructure in place to design the path to production for your applications.

> **Note:**
>
> If you would like to learn more about the Carvel CLIs used in the [infra_install.sh](infra_install.sh) script (`vendir`, `ytt`, and `kapp`), check out [Carvel] or this [Carvel demo].




[builder]: https://buildpacks.io/docs/concepts/components/builder
[Carvel]: https://carvel.dev
[Carvel demo]: https://github.com/ciberkleid/carvel-demo
