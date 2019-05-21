# Creating a Source-to-Image build pipeline in OKD

The Source-to-Image build described in the previous section is perfect for local development, or maintaining a builder image with a code pipeline, but if you have access to an [OKD](https://www.okd.io/) or OpenShift cluster (or [Minishift](https://github.com/minishift/minishift)), you can setup the entire workflow using OKD `buildConfigs`, not only to build and maintain the builder image, but to use the builder image to create the application image and subsequent runtime image, automatically.  The images can be rebuilt automatically when downstream images change, and can trigger OKD deploymentConfigs to redeploy applications running from these image.


## Part 1: Build the Builder Image in OKD

Just as with the local Source-to-Image usage, the first step in the process is creating the builder image that will be used to build our goHelloWorld, and can be re-used to compile other Go-based applications.  This first build step will be a Docker build, just like before, and pulls the Dockerfile and s2i scripts from a Git repository to build the image, so those files must be committed and available in a public Git repo, or you can use the companion GitHub repo for this article: [https://github.com/clcollins/golang-s2i.git](https://github.com/clcollins/golang-s2i.git).

_Note:_ OKD buildConfigs do not require Git repos used as the source to be public.  To use a private repo, you must setup deploy keys and link the keys to a builder service account.  This is not difficult, but for simplicity's sake this exercise will just use a public repository.


### Create an ImageStream for the builder image

The buildConfig will create a builder image for us to use to compile the goHelloWorld app, but first, we need a place to store the image.  In OKD, that place is an `imageStream`.

An [ImageStream](https://docs.okd.io/latest/architecture/core_concepts/builds_and_image_streams.html#image-streams) and its tags are like a manifest or list of related images and image tags.  It serves as an abstraction layer that allows you to reference an image, even if the image itself has changed.  Think of it as a collection of aliases that reference specific images, and as images are updated, will automatically point to the new image version.  The ImageStream itself is nothing but these "aliases" - just metadata about real images stored in a registry.

An image stream can be crated with the `oc create imagestream <name>` command, or it can be created from a YAML file with `oc create -f <filename>`.  Either way, a brand-new image stream is a small placeholder object, and is empty until it is populated with image references, either manually (who wants to do things manually?) or with a buildConfig.

Our golang-builder imageStream looks like this:

```
# imageStream-golang-builder.yaml
---
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  generation: 1
  name: golang-builder
spec:
  lookupPolicy:
    local: false
```

Other than a name, and a (mostly) empty spec, there is nothing really there.

_Note:_ The `lookupPolicy` has to do with allowing Kubernetes-native components to resolve ImageStream references, since ImageStreams are OKD-native, and not a part of the Kubernetes core.   This topic is out-of-scope for our example here, but you can read more about how it works in the [OKD "Using ImageStreams with Kubernetes Resources" Documentation](https://docs.okd.io/latest/dev_guide/managing_images.html#using-is-with-k8s)

Create an ImageStream for the builder image and its progeny:

```
$ oc create -f imageStream-golangBuilder.yaml

# Check the ImageStream
$ oc get imagestream golang-builder
NAME                                            DOCKER REPO                                                      TAGS	   UPDATED
imagestream.image.openshift.io/golang-builder   docker-registry.default.svc:5000/golang-builder/golang-builder
```

Note that the newly created image stream has no tags, and has never been updated.


## Create a BuildConfig for the builder image

In OKD, a [BuildConfig](https://docs.okd.io/latest/dev_guide/builds/index.html#defining-a-buildconfig) describes the way to build container images from a specific source, and triggers for when they build.  Don't be thrown off by the language here.  Just as you might say you build and re-build the same image from a Dockefile, but in reality you have built multiple images, a BuildConfig builds and rebuilds the "same image" but in reality creates multiple images. (And suddenly, the reason for ImageStreams become much clearer!)

Our builder image BuildConfig describes how to build and re-build our builder image(s).  The core of the BuildConfig is made up of four important parts:

1.  the build source
2.  the build strategy
3.  the output of the build
4.  build triggers

The Build Source describes (predictably) where the source used to run the build comes from.  The builds described by the golang-builder BuildConfig will use the Dockerfile and s2i scripts we created previously, and using the Git-type build source, clone a Git repository to get the files with which to do the builds:

```
source:
  type: Git
  git:
    ref: master
    uri: https://github.com/clcollins/golang-s2i.git
```

The Build Strategy describes just what the build will do with the source files from the build source.  The golang-builder BuildConfig mimics the `docker build` we did previously to build our local builder image, by using the Docker-type build strategy:

```
strategy:
  type: Docker
  dockerStrategy: {}
```

The `dockerStrategy` build type tells OKD to build a Docker image from the Dockerfile contained in the source specified by the build source.

The Build Output tells the BuildConfig what to do with the resulting image.  In our case, we specify the ImageStream we created above, and a tag to give to the image.  As with our local build, we're tagging it with `golang-builder:1.12`, just as a reference to the Go version inherited from the parent image.

```
output:
  to:
    kind: ImageStreamTag
    name: golang-builder:1.12
```

Finally, the BuildConfig defines a set of Build Triggers - events that will cause the image to be rebuilt automatically.  For this BuildConfig, an change to the BuildConfig configuration, or and update to the upstream image (golang:1.12), will trigger a new build.

```
  triggers:
  - type: ConfigChange
  - imageChange:
      type: ImageChange
```

Using the [builder image BuildConfig from the accompanying GitHub repo](https://github.com/clcollins/golang-s2i/blob/master/okd/buildConfig-golang-builder.yaml) as a reference (or just using the file itself), create a BuildConfig YAML file and use it to create the BuildConfig:

```
$ oc create -f buildConfig-golang-builder.yaml

# Check the BuildConfig
$ oc get bc golang-builder
NAME             TYPE      FROM         LATEST
golang-builder   Docker    Git@master   1
```

Because the BuildConfig included the "ImageChange" trigger, it immediately kicks off a new build.  You can check that the build was created with the `oc get builds` command.

```
# Check the Builds
$ oc get build
NAME               TYPE      FROM          STATUS     STARTED              DURATION
golang-builder-1   Docker    Git@8eff001   Complete   About a minute ago   13s
```

While the build is running, and after it has completed, you can view its logs with `oc logs -f <build name>`, and see the Docker build output as you would locally.

```
$ oc logs -f golang-builder-1-build
Step 1/11 : FROM docker.io/golang:1.12
 ---> 7ced090ee82e
Step 2/11 : LABEL maintainer "Chris Collins <collins.christopher@gmail.com>"
 ---> 7ad989b765e4
Step 3/11 : ENV CGO_ENABLED 0 GOOS linux GOCACHE /tmp STI_SCRIPTS_PATH /usr/libexec/s2i SOURCE_DIR /go/src/app
 ---> 2cee2ce6757d

<...>
```

If you did not include any build triggers (or did not have them in the right place), your build may not have started automatically.  You can manually kick off a new build with the `oc start-build` command:

```
$ oc start-build golang-builder

# Or, if you want to automatically tail the build log
$ oc start-build golang-builder --follow
```

When the build is completed, the resulting image is tagged and pushed to the integrated image registry, and the ImageStream is updated with the new image's information.  Check the ImageStream with the `oc get imagestream` command to see that the new tag exists:

```
$ oc get imagestream golang-builder
NAME             DOCKER REPO                                                      TAGS      UPDATED
golang-builder   docker-registry.default.svc:5000/golang-builder/golang-builder   1.12      33 seconds ago
```


## Part 2: Build the Application Image in OKD

Now we have a builder image for our Golang applications created, and stored within OKD.  Now we can use it to compile all of our Go apps.  First on the block is our example goHelloWorld app, from our previous local build example.  You will recall that goHelloWorld is a simple Go app that just outputs `Hello World!` when run.

Just as we did in the local example with the `s2i build` command, we can tell OKD to use our builder image and Source-To-Image to build the application image for goHelloWorld, compiling the Go binary from the source code in the [GoHelloWorld Github Repository](https://github.com/clcollins/goHelloWorld.git).  This can be done with a BuildConfig with a `sourceStrategy` build.


## Create an ImageStream for the Application Image

First things first, though, we need to create an ImageStream to manage the image created by the the BuildConfig.  The ImageStream itself is just like the golang-builder ImageStream, just with a different name.  Create it with `oc create is` or using a YAML file from the GitHub repo:

```
$ oc create -f imageStream-goHelloWorld-appimage.yaml
imagestream.image.openshift.io/go-hello-world-appimage created
```


## Create a BuildConfig for the Application Image

Just as we did with the builder image BuildConfig, this BuildConfig will use the Git Source option to clone our source code from the goHelloWorld repository.

```
source:
  type: Git
  git:
    uri: https://github.com/clcollins/goHelloWorld.git
```

Instead of using a DockerStrategy build to create an image from a Dockerfile, this BuildConfig will use the  SourceStrategy, to build the image using Source-to-Image.

```
strategy:
  type: Source
  sourceStrategy:
    from:
      kind: ImageStreamTag
      name: golang-builder:1.12
```

Note the `from:` hash in the sourceStrategy.  This tells OKD to use the golang-builder:1.12 image we created above for the S2I build.

The BuildConfig will output to the new appimage image stream we created above, and we'll include config and image change triggers to kick off new builds automatically if anything is updated:

```
output:
  to:
    kind: ImageStreamTag
    name: go-hello-world-appimage:1.0
triggers:
- type: ConfigChange
- imageChange:
    type: ImageChange
```

Once again, create a buildConfig or use the one from the GitHub repo:

```
$ oc create -f buildConfig-goHelloWorld-appimage.yaml
```

The new build shows up along side the golang-builder build, and as before, since image change triggers are specified, the build starts immediately:

```
$ oc get builds
NAME                        TYPE      FROM          STATUS     STARTED          DURATION
golang-builder-1            Docker    Git@8eff001   Complete   8 minutes ago    13s
go-hello-world-appimage-1   Source    Git@99699a6   Running    44 seconds ago
```

Watch the build logs if you want using the `oc logs -f` command.  Once the application image build is complete, it is pushed to the ImageStream we specified.  The the new ImageStream tag was created:

```
$ oc get is go-hello-world-appimage
NAME                      DOCKER REPO                                                               TAGS      UPDATED
go-hello-world-appimage   docker-registry.default.svc:5000/golang-builder/go-hello-world-appimage   1.0       10 minutes ago
```

Success!  The goHelloWorld app was cloned from source into a new image, and compiled and tested using our Source-to-Image scripts.  We can use the image as-is, but as with our local Source-to-Image builds, we can do better, and create an image with just the new Go binary in it.


## Part 3: Build the Runtime Image in OKD

Now that the application image has been created with a compiled Go binary for the goHelloWorld app, we can use something called a Chain Build flow to mimic when we extracted the binary from our local application image and created a new runtime image with just the binary in it.


### Create an ImageStream for the Runtime image

Again, though, the first step is to create an ImageStream image for the new runtime image:

```
# Create the ImageStream
$ oc create -f imageStream-goHelloWorld.yaml
imagestream.image.openshift.io/go-hello-world created

# Get the ImageStream
$ oc get imagestream go-hello-world
NAME             DOCKER REPO                                                      TAGS      UPDATED
go-hello-world   docker-registry.default.svc:5000/golang-builder/go-hello-world
```

### Chain Builds

Chain builds are when one or more BuildConfigs are used to compile software or assemble artifacts for an application, and those artifacts are saved and used by a subsequent BuildConfig to generate a runtime image without re-compiling the code.

![A Chain Build workflow](img/chaining-builds.png) A Chain Build workflow. Source: [OKD Chain Builds Documentation](https://docs.okd.io/3.11/dev_guide/builds/advanced_build_operations.html#dev-guide-chaining-builds)


### Create a BuildConfig for the Runtime image

The runtime BuildConfig uses the DockerStrategy build, to build the image from a Dockerfile - the same thing we did with the builder image BuildConfig.  This time, however, the source is not a Git source, but a Dockerfile source.

What is the Dockerfile Source?  It's an inline Dockerfile!  Instead of cloning a repo with a Dockerfile in it and building that, we specify the Dockerfile in the BuildConfig itself.  This is especially appropriate with our runtime Dockerfile, because it's just three lines long:

```
  source:
    type: Dockerfile
    dockerfile: |-
      FROM scratch
      COPY app /app
      ENTRYPOINT ["/app"]
    images:
    - from:
        kind: ImageStreamTag
        name: go-hello-world-appimage:1.0
      paths:
      - sourcePath: /go/src/app/app
        destinationDir: "."
```

Note that the Dockerfile in the Dockerfile Source definition above is is the same as the Dockerfile we used in the previous article in the series, when we built the slim goHelloWorld image locally using the binary we extracted with the S2I `save-artifacts` script.

Also something to note: `scratch` is a reserved word.  It does not define an _actual_ image, but that it is the first layer is nothing, and subsequent build operations build upon that.  It is defined with `kind: DockerImage`, but does not have a registry or group/namespace/project string.

The `images` section of the Dockerfile source describes the source of the artifact(s) to be used in the build, in this case, from the appimage generated earlier.  The `paths` sub-section describes where to get the binary (in the `/go/src/app` directory of the app image, get the `app` binary), and  where to save it (in the current working directory of the build itself: `"."`). This allows the `COPY app /app` to grab the binary from the current working directory and add it to `/app` in the runtime image.

_Note:_ `paths` is an array of source and destination path _pairs_.  Each individual entry in the list consists of a source and destination. In the example above, there is just the one entry, because there is just the single binary to copy.

The Docker strategy is then used to build the inline Dockerfile,

```
  strategy:
    type: Docker
    dockerStrategy: {}
```

And once again, output to the ImageStream created earlier, and include build triggers to automatically kick off new builds:

```
  output:
    to:
      kind: ImageStreamTag
      name: go-hello-world:1.0
  triggers:
  - type: ConfigChange
  - imageChange:
      type: ImageChange
```

Create a BuildConfig YAML or use the runtime BuildConfig from the GitHub Repo:

```
$ oc create -f buildConfig-goHelloWorld.yaml
buildconfig.build.openshift.io/go-hello-world created
```

If you watch the logs, you'll notice the first step is `FROM scratch`, confirming we're adding the compiled binary to a blank image.

```
$ oc logs -f pod/go-hello-world-1-build
Step 1/5 : FROM scratch
 --->
Step 2/5 : COPY app /app
 ---> 9e70e6c710f8
Removing intermediate container 4d0bd9cef0a7
Step 3/5 : ENTRYPOINT /app
 ---> Running in 7a2dfeba28ca
 ---> d697577910fc

<...>
```

Once the build is completed, check the ImageStream tag to validate that the new image was pushed to the registry and ImageStream updated:

```
$ oc get imagestream go-hello-world
NAME             DOCKER REPO                                                      TAGS      UPDATED
go-hello-world   docker-registry.default.svc:5000/golang-builder/go-hello-world   1.0       4 minutes ago
```

Make a note of the `DOCKER REPO` string for the image.  It will be used in the next section to run the image.


### Did we create a tiny, binary-only image?

Finally, let's validate that we did, indeed, build a tiny image with just the binary.

Check out the image details.  First, get the actual image's name from the ImageStream:

```
$ oc describe imagestream go-hello-world
Name:			go-hello-world
Namespace:		golang-builder
Created:		42 minutes ago
Labels:			<none>
Annotations:		<none>
Docker Pull Spec:	docker-registry.default.svc:5000/golang-builder/go-hello-world
Image Lookup:		local=false
Unique Images:		1
Tags:			1

1.0
  no spec tag

  * docker-registry.default.svc:5000/golang-builder/go-hello-world@sha256:eb11e0147a2917312f5e0e9da71109f0cb80760e945fdc1e2db6424b91bc9053
      13 minutes ago
```

The image itself is listed at the bottom, described with the SHA hash `sha256:eb11e0147a2917312f5e0e9da71109f0cb80760e945fdc1e2db6424b91bc9053`

_Note:_ Yours will have a different hash.

Get the details of the image itself using the hash:

```
$ oc describe image sha256:eb11e0147a2917312f5e0e9da71109f0cb80760e945fdc1e2db6424b91bc9053
Docker Image:	docker-registry.default.svc:5000/golang-builder/go-hello-world@sha256:eb11e0147a2917312f5e0e9da71109f0cb80760e945fdc1e2db6424b91bc9053
Name:		sha256:eb11e0147a2917312f5e0e9da71109f0cb80760e945fdc1e2db6424b91bc9053
Created:	15 minutes ago
Annotations:	image.openshift.io/dockerLayersOrder=ascending
		image.openshift.io/manifestBlobStored=true
		openshift.io/image.managed=true
Image Size:	1.026MB
Image Created:	15 minutes ago
Author:		<none>
Arch:		amd64
Entrypoint:	/app
Working Dir:	<none>
User:		<none>
Exposes Ports:	<none>
Docker Labels:	io.openshift.build.name=go-hello-world-1
		io.openshift.build.namespace=golang-builder
Environment:	PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
		OPENSHIFT_BUILD_NAME=go-hello-world-1
		OPENSHIFT_BUILD_NAMESPACE=golang-builder
```

Notice the image size, `Image Size: 1.026MB`, exactly as desired.  The image is a scratch image with just the binary contained within!


## Conclusion: Run a Pod with the Runtime Image

Using the runtime image we just created, let's create a pod on-demand and run it, and validate that it still works.

This almost never happens in Kube/OKD, but run a pod, just a pod, by itself.

```
$ oc run -it  go-hello-world --image=docker-registry.default.svc:5000/golang-builder/go-hello-world:1.0 --restart=Never
Hello World!
```

Everything is working as expected - the image runs and outputs "Hello World!" just as it did in the previous, local Source-to-Image builds.

By creating this workflow in OKD, we can now use the `golang-builder` Source-to-Image image for any Go applications.  This builder image is in place, and pre-built for any other applications we desire, and it will auto-update and rebuild itself anytime the upstream `golang:1.12` image changes.

New apps can be built automatically using the source-to-image build by creating a chain build strategy in OKD, with an appimage buildConfig to compile the source, and the runtime buildConfig to create the final image.  Using the build triggers, any change to the source code in the git repo will trigger a rebuild through the entire pipeline, rebuilding the appimage and the runtime image automatically.  This is a great way to maintain updated images for any application.  Paired with a OKD deploymentConfig with an image build trigger, long-running applications (eg. webapps) will be automatically redeployed when new code is committed.

Source-to-Image is an ideal way to develop builder images to build and compile our Go applications in a repeatable way, and it just gets better when paired with OKD BuildConfigs!
