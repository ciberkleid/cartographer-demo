## Cluster Setup

This section will cover the following steps:

- [Prerequisites](README-setup.md/#Prerequisites)
- [Create a Kubernetes cluster](README-setup.md/#Create-a-Kubernetes-cluster)
- [Create an ops repo in GitHub](README-setup.md/#Create-an-ops-repo-in-GitHub)
- [SSH access to GitHub](README-setup.md/#SSH-access-to-GitHub)
- [Access to Docker Hub or Google Artifact Registry](README-setup.md/#Access-to-Docker-Hub-or-Google-Artifact-Registry)
- [Download installation files](README-setup.md/#Download-installation-files)
- [Install tooling on cluster](README-setup.md/#Install-tooling-on-cluster)
- [Verify the installation](README-setup.md/#Verify-the-installation)

#### Prerequisites

- [Carvel] tool suite
- A GitHub account
- A DockerHub or Google Cloud account

> Note: 
> You can use any git or image registry of your choice, but the instructions in this repo are written for GitHub and either Docker Hub or Google Artifact Repository.

#### Create a Kubernetes cluster

If you wish to use an existing Kubernetes cluster, make sure your `kubectl` context is set appropriately.

Alternatively, you can start a cluster locally on your machine using _Kubernetes in Docker_ (kind).

To create a cluster locally, install [kind] and [Docker] first, then run the following command:
```shell
# Create local cluster
kind create cluster --name cartographer-demo
```

#### Create an ops repo in GitHub

Using your browser, log into your [GitHub](https://github.com) account and create a new repository called `cartographer-demo-ops`.
You will use this later to save Kubernetes manifests for your applications.

#### SSH access to GitHub

To enable the workflow to write to the `cartographer-demo-ops` repo, you need to provide SSH access from the cluster.

To set this up, run the following commands.
These will create a public and private key, as well as a known hosts file.
```shell
# Create known_hosts file, public and private key in a new directory
mkdir setup/access-control/.ssh
ssh-keygen -t rsa -b 4096 -f setup/access-control/.ssh/id_rsa -q -N ""
ssh-keyscan github.com > setup/access-control/.ssh/known_hosts
```

You should see three new files, as shown below.
```shell
$ ls -l setup/access-control/.ssh
total 24
-rw-------  1 ciberkleid  staff  3414 Dec 28 09:41 id_rsa
-rw-r--r--  1 ciberkleid  staff   762 Dec 28 09:41 id_rsa.pub
-rw-r--r--  1 ciberkleid  staff   656 Dec 28 09:40 known_hosts
```

> Note:
> `.ssh/` is listed in the `.gitignore` file, to prevent credential secrets from being checked into the git repository.

Copy the contents of the public key file to the clipboard.
```shell
# Copy public key to clipboard
pbcopy < setup/access-control/.ssh/id_rsa.pub
```

In your browser, go back to [github.com](https://github.com). Under your account, click on Settings --> SSH and GPG Keys --> New SSH key.
Give the key any title (e.g. _"Cartographer"_), and type <Ctrl+V> to paste the public key from the clipboard.
Then click Add SSH key.

You will use the known_hosts and private key later to set up a secret in Kubernetes that will authenticate against the public key in GitHub.

#### Access to Docker Hub or Google Artifact Registry

To enable the workflow to publish images to the image registry, you need to provide write access from the cluster.

Start by creating a new file to provide custom configuration values to Cartographer.
To create your custom config file, make a copy of the example file provided in this repo:
```shell
# Create a new config file
cp config-REDACTED.yaml config.yaml
```

Open your new `config.yaml` file and find the section for registry configuration.
Notice the sample file includes an option for Docker Hub configuration and another for Google Artifact Registry configuration.
Which one should you use?
The advantage of Docker Hub is that creating an account and a personal access token is straightforward.
However, Docker Hub applies rate limits to the free tier. This is not necessarily an issue, but if you reach the rate limit and this becomes an inconvenience, you can use another image registry.
As an example, instructions for using Google Artifact Registry as an alternative to Docker Hub are included below.

To use [Docker Hub](https://www.docker.com), use your browser to log into your account.
Navigate to Account Settings --> Security --> Access Tokens. Click on "New Access Token".
Give the token any description you like and make sure it includes "write" permissions. Copy the token to your clipboard.

In your new `config.yaml` file, edit the settings so that the username and password fields contain your username and the access token you just created.
```shell
registry:
  server: https://index.docker.io/v1/
  username: ciberkleid
  # Use a personal access token as the password
  password: abcd1234-ab12-ab12-ab12-abcdef123456
```

> Note:
> `config.yaml` is listed in the `.gitignore` file, to prevent credential secrets from being checked into the git repository.

To use Google Artifact Registry on [GCP](console.cloud.google.com), you must have a project with a "billing account". Follow the instructions [here](https://cloud.google.com/artifact-registry/docs/access-control) to:
- Create a Docker repository called `cartographer-demo`.
- Configure a service account with IAM roles `Artifact Registry Reader` and `Artifact Registry Repository Administrator`.
- Create a private JSON key for the service account and save the json key file as `setup/access-control/.ssh/gcp-service-account.json`.

In your new `config.yaml` file, comment out the settings for Docker Hub and comment in the settings for GCP.
Edit the settings so that the server matches the Docker registry you just created.
Leave the key as the literal `_json_key`.
```shell
## GCP settings:
registry:
  server: https://us-east4-docker.pkg.dev
  username: _json_key
  # Username must be "_json_key".
  # Copy your key file to setup/access-control/.ssh/gcp-service-account.json
```

In either case—Docker Hub or Google Artifact Registry—you will use this configuration later to set up a secret in Kubernetes that will authenticate against the image registry.

#### Download installation files

Carvel's vendir tool makes it easy to download all the installation files you will need.
Run the following command:
```shell
# Download installation files
ytt -f setup/vendir.yml \
    --data-values-file config.yaml \
    | vendir sync --chdir setup -f-
```

When this command completes, you should see a new directory called `setup/vendir` with the installation files for each of the products you will need for this demo.
The directory should look like this:
```shell
$ tree setup/vendir
setup/vendir
├── cartographer
│   └── cartographer.yaml
├── cert-manager
│   └── cert-manager.yaml
├── flux2
│   └── install.yaml
├── kapp-controller
│   └── release.yml
├── knative-serving
│   ├── serving-core.yaml
│   └── serving-crds.yaml
├── kpack
│   └── release-0.5.0.yaml
├── secretgen-controller
│   └── release.yml
├── tekton
│   └── release.yaml
├── tekton-catalog
│   └── git-cli
│       └── git-cli.yaml
└── tekton-pipeline
    └── release.yaml

11 directories, 11 files
```

Again, don't worry if you are not familiar with these tools.
You will get the necessary insight into each one at the appropriate moment in this demo.

If you're curious, feel free to look through the [vendir.yml](setup/vendir.yml) file to see the configuration for pulling in the dependency files.
You can also learn more about vendir on the [Carvel] website.

#### Install tooling on cluster

The commands below will:
- Create two namespaces where you can deploy your applications (apps-dev and apps-prod)
- Set up access configuration (secrets, roles, service accounts, etc), in part using the git and image registry credential information you provided earlier
- Install all the required tools using the files downloaded by `vendir` in the previous step

You may notice that the commands below use `ytt` and `kapp` to process and apply yaml configuration.
ytt processes any templates and overlays found in the raw configuration files and creates pure yaml as output.
This pure yaml can then be passed to any compatible command, such as `kubectl apply -f-`.
In this demo, however, you will use `kapp deploy` rather than `kubectl apply`
because kapp offers additional capabilities for managing multiple related resources.
If you are curious, you can learn more about ytt and kapp on the [Carvel] website.

Run the following commands.
You can copy and paste all of them at once into your terminal window.
Note that they may take a couple of minutes to complete.
```shell
# Create namespaces to deploy applications
kubectl create ns apps-dev
kubectl create ns apps-prod

# Install credentials/RBAC
ytt -f setup/access-control \
    --data-values-file config.yaml \
    | kapp deploy -a access-control -f- -n default --yes

# Install tools
ytt -f setup/vendir/cert-manager \
    --data-values-file config.yaml \
    | kapp deploy -a cert-manager -f- -n default --yes

ytt -f setup/vendir/secretgen-controller \
    --data-values-file config.yaml \
    | kapp deploy -a secretgen-controller -f- -n default --yes
  
ytt -f setup/vendir/kapp-controller \
    --data-values-file config.yaml \
    | kapp deploy -a kapp-controller -f- -n default --yes

ytt -f setup/vendir/cartographer \
    -f setup/overlays/cartographer \
    --data-values-file config.yaml \
    | kapp deploy -a cartographer -f- -n default --yes

ytt -f setup/vendir/flux2 \
    --data-values-file config.yaml \
    | kapp deploy -a flux2 -f- -n default --yes

ytt -f setup/vendir/tekton-pipeline \
    --data-values-file config.yaml \
    | kapp deploy -a tekton -f- -n default --yes

ytt -f setup/vendir/kpack \
    -f setup/overlays/kpack \
    --data-values-file config.yaml \
    | kapp deploy -a kpack -f- -n default --yes

ytt -f setup/vendir/knative-serving \
    --data-values-file config.yaml \
    | kapp deploy -a knative-serving -f- -n default --yes

ytt -f setup/vendir/tekton-catalog \
    -f setup/overlays/tekton-catalog \
    --data-values-file config.yaml \
    | kapp deploy -a tekton-catalog -f- -n default --yes
```

When the commands complete, proceed to the next section to verify the installation.

#### Verify the installation

###### Verify overall installation

Review the results of the installation using the following command.
Everything should look healthy (green).
```shell
kapp list
```

You can also get the list of resources associated with any application using, for example:
```shell
kapp inspect -a cartographer
```

If you would like to see the secrets, roles, and service accounts that were created in apps-dev and apps-prod namespaces, you can run the following command:
```shell
kapp inspect -a access-control
```

You can still also, of course, run any `kubectl get` commands you are already familiar with to explore the results of the installation.

###### Verify creation of kpack builder

kpack is the tool you will be using to turn source code into container images.

For each image it needs to build, kpack needs to create a Pod in which it can do the work of retrieving your source code and composing an OCI image.

This Pod uses an image called a `builder`.
The builder image, however, is not part of the kpack installation.
Rather, you need to create the builder yourself.

This repo contains the configuration you need to create the builder and, in fact, this configuration was included when you installed all dependencies in the previous step.
If you look at the builder configuration in the [kpack overlay](setup/overlays/kpack/kpack.yaml), you will see that a builder is created from a `stack` (base image) and `store` (set of language-specific buildpacks).

Since the overlay was included in the kpack installation you carried out earlier, all you need to do now is to verify that the builder was indeed created. 
Run the following command:
```shell
kubectl get clusterbuilder builder
```

The response should look something like this, with your image repository instead of the one shown below:
```shell
$ kubectl get clusterbuilder builder
NAME      LATESTIMAGE                                                                                                    READY
builder   ciberkleid/cartographer-demo-builder@sha256:12151ad442cbe6194a7377b413fabfd7bceacffb777ca37aa5bb41a8a6a4a94c   True
```

The output above indicates that the builder image was successfully pushed to the registry.
However, if you like, you can check your image registry to validate that the image is there.

<hr />

That concludes the setup.
You are now ready to proceed with the Cartographer demo!
Please return to the main [README.md](./README.md) to continue.


[Carvel]: https://carvel.dev
[kind]: https://kind.sigs.k8s.io
[Docker]: https://docs.docker.com