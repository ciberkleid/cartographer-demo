## Cartographer Fundamentals and Syntax

This section introduces basic concepts and syntax for configuring Cartographer.

This section will cover the following steps:

- [Configure dependencies](README-carto101.md/#Configure-dependencies)
- [Hook dependencies into Cartographer using Templates](README-carto101.md/#Hook dependencies-into-Cartographer-using-Templates)
- [Parameterize app specific details using Workloads](README-carto101.md/#Parameterize-app-specific-details-using-Workloads)
- [Associate Workloads with Templates using Supply Chains](README-carto101.md/#Associate-Workloads-with-Templates-using-Supply-Chains)
- [Chain resources together](README-carto101.md/#Chain-resources-together)

#### Configure dependencies

Assume the first action you want to automate is polling a source code repository for new commits.

By design, Cartographer does not have this capability.
Therefore, you first need to choose a tool that does.
One option is [Flux GitRepository](https://fluxcd.io/docs/components/source/gitrepositories).

Begin by configuring the Flux resource.
For example:
```shell
apiVersion: source.toolkit.fluxcd.io/v1beta1
kind: GitRepository
metadata:
  name: hello-world
  labels:
    app.kubernetes.io/part-of: hello-world
spec:
  interval: 1m
  url: https://github.com/my-org/hello-world
  ref: main
```

This resource will poll the specified url every minute.
Each time it finds a new commit, it will update its status.
In the example below showing the status of an existing GitRepository resource, you can see that the field `status.artifact.url` contains a reference to a compressed source archive with the latest code.
```shell
status:
  artifact:
    lastUpdateTime: "2022-01-10T10:28:32Z"
    path: /data/gitrepository/default/hello-world/f71850b1bfd479a3e3d4c4b80079698efb744eb8.tar.gz
    revision: main/f71850b1bfd479a3e3d4c4b80079698efb744eb8
    url: http://github.com/gitrepository/default/hello-world/f71850b1bfd479a3e3d4c4b80079698efb744eb8.tar.gz
  conditions:
  - lastTransitionTime: "2022-01-10T10:28:32Z"
    message: 'Git repoistory artifacts are available at:
      /data/gitrepository/default/hello-world/f71850b1bfd479a3e3d4c4b80079698efb744eb8.tar.gz'
    reason: GitOperationSucceed
    status: "True"
    type: Ready
  url: http://github.com/gitrepository/default/hello-world/latest.tar.gz
```

> **_Note:_** 
> 
> At runtime, you can check the status using either of the following commands:
> 
> `kubectl get gitrepository hello-world -o json | jq '.items[0].status'`
> 
> `kubectl describe gitrepository hello-world`

#### Hook dependencies into Cartographer using Templates

To enable Cartographer to submit the GitRepository configuration to Kubernetes and monitor the status for the desired field, you need to wrap the GitRepository configuration with a Cartographer Template API.
Cartographer provides several [templates](https://cartographer.sh/docs/v0.1.0/reference/template).
In this case, `ClusterSourceTemplate` is appropriate since the template's output fields match the GitRepository output fields.

The wrapped configuration would look like this:
```shell
apiVersion: carto.run/v1alpha1
kind: ClusterSourceTemplate
metadata:
  name: workload-git-repository
spec:

  # ClusterSourceTemplate output fields
  # specifying jsonpath to the desired value
  urlPath: .status.artifact.url
  revisionPath: .status.artifact.revision
  
  template:  
    # The original resource configuration
    apiVersion: source.toolkit.fluxcd.io/v1beta1
    kind: GitRepository
    metadata:
      name: hello-world
      labels:
        app.kubernetes.io/part-of: hello-world
    spec:
      interval: 1m
      url: https://github.com/my-org/hello-world
      ref: main
```

#### Parameterize app specific details using Workloads

What happens when you want to poll a second git repository?

Cartographer enables you to parameterize the workload-specific values and provide custom values using a [Workload API](https://cartographer.sh/docs/v0.1.0/reference/workload/#workload).

This enables app operators to create templates that can be reused across applications and development teams, and it provides developers a way to use the templated workflows without the burden of owning the implementation.

The Workload that a developer would submit for this example might look like this:
```shell
apiVersion: carto.run/v1alpha1
kind: Workload
metadata:
  name: hello-world
  labels:
    apps.tanzu.vmware.com/workload-type: web-app
spec:
  serviceAccountName: workload-service-account
  source:
    git:
      url: https://github.com/my-org/hello-world
      ref:
        branch: main
```

You can now update the Template to reference values from the Workload:
```shell
apiVersion: carto.run/v1alpha1
kind: ClusterSourceTemplate
metadata:
  name: workload-git-repository
spec:
  urlPath: .status.artifact.url
  revisionPath: .status.artifact.revision
  template:
    apiVersion: source.toolkit.fluxcd.io/v1beta1
    kind: GitRepository
    metadata:
      name: $(workload.metadata.name)$
      labels:
        app.kubernetes.io/part-of: $(workload.metadata.name)$
    spec:
      interval: 1m
      url: $(workload.spec.source.git.url)$
      ref: $(workload.spec.source.git.ref)$
```

#### Associate Workloads with Templates using Supply Chains

The next step is to associate the Workload with a specific Template, or more commonly, a sequence of Templates.

Given the configuration above, a new Workload will not cause Cartographer to create a GitRepository. Why not?
Imagine that there are more templates that have been defined—for testing code, building an image, sending a notification, and so on.
Cartographer cannot infer from the information in the Workload which templates to instantiate, and in which order.

The missing piece is called a Supply Chain.
A Supply Chain lays out a particular sequence of templates, and it instructs Cartographer on how to pass the outputs of one template as input to another.

Take a look at this simple Supply Chain containing only the template we have defined so far.
Notice that the `selector` links the Workload to the Supply Chain, and the `templateRef` links the Supply Chain to the Template.
```shell
apiVersion: carto.run/v1alpha1
kind: ClusterSupplyChain
metadata:
  name: web-app
spec:
  selector:
    apps.tanzu.vmware.com/workload-type: web-app

  resources:
    - name: source-provider
      templateRef:
        kind: ClusterSourceTemplate
        name: workload-git-repository
```

Now when a developer submits a Workload, the Supply Chain with a matching selector will begin sequentially submitting the resources in the Supply Chain for that Workload.


#### Chain resources together

In the simple example above, the Supply Chain contains only one resource—a ClusterSourceTemplate that outputs a blob-url to the latest code committed.

The next step might be to build an image.

Following the steps above, you would compose the template by defining the configuration for the tool of choice (let's use kpack in this example), wrapping it in the appropriate tempate (in this case, ClusterImageTemplate), and parameterizing the values that are provided by the Workload.

The result might look like this:
```yaml
apiVersion: carto.run/v1alpha1
kind: ClusterImageTemplate
metadata:
  name: workload-kpack-image
spec:
  # ClusterImageTemplate output field
  # specifying jsonpath to the desired value
  imagePath: .status.latestImage
  
  template:
    # The kpack Image resource configuration
    apiVersion: kpack.io/v1alpha1
    kind: Image
    metadata:
      name: $(workload.metadata.name)$
      labels:
        app.kubernetes.io/part-of: $(workload.metadata.name)$
    spec:
      tag: us-east4-docker.pkg.dev/fe-ciberkleid/cartographer-demo/$(workload.metadata.name)$
      serviceAccount: service-account
      builder:
        kind: ClusterBuilder
        name: builder
      source:
        blob:
          # Placeholder for Cartographer to populate using ClusterSourceTemplate output
          url: $(source.url)$
```

Notice the last field, `url`, is parameterized using `source` instead of`workload`.

The last step is to tell Cartographer which resource that `source` is, so it can retrieve the url from that source and inject it here.

You do this in the Supply Chain:
```yaml
  resources:
    - name: source-provider
      templateRef:
        kind: ClusterSourceTemplate
        name: workload-git-repository

    - name: image-builder
      templateRef:
        kind: ClusterImageTemplate
        name: workload-kpack-image
      sources:
        - resource: source-provider
          # In ClusterTemplate, use $(sources.new-source.url)$
          # Can also use $(source.url) if there is only one source
          name: new-source
```

It is possible to define parameters as well as a source of values. Please visit the documentation for more information on using parameters.

<hr />

That concludes the setup.
You are now ready to proceed with the Cartographer demo!
Please return to the main [README.md](./README.md) to continue.

[Carvel]: https://carvel.dev
[kind]: https://kind.sigs.k8s.io
[Docker]: https://docs.docker.com