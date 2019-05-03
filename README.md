# Writing your own Golang Builder with Source-to-Image

TODO: Write into


## What is s2i, and why use it

The idea behind Source to Image (s2i, or sti) is to make a "builder" image with all the libraries and build tools needed to compile an application (as with Golang), or install dependencies (like Python's Pip or Ruby's Bundler), and a set of scripts at a well-known location that can be called by Source To Image to build, test and run the application.  Once the builder image is created, Source to Image can take code from a repository, inject it into the build image, compile or install dependencies, and generate an application image with the final application ready to go.

Source to Image makes it easy to reproduce consistent images and allows developers to focus on their applications rather than Docker images and containers.

The real beauty of source to image in my opinion, though, is the ability to use builder images as templates, so that similar applications with similar configurations can be deployed without managing Dockerfiles and Docker builds for every app.


## What do you need for s2i

There are only four files required to make an image a Source To Image-compatible image.  Straight from the s2i docs:

| File                   | Required? | Description                                                  |
|------------------------|-----------|--------------------------------------------------------------|
| Dockerfile             | Yes       | Defines the base builder image                               |
| s2i/bin/assemble       | Yes       | Script that builds the application                           |
| s2i/bin/usage          | No        | Script that prints the usage of the builder                  |
| s2i/bin/run            | Yes       | Script that runs the application                             |
| s2i/bin/save-artifacts | No        | Script for incremental builds that saves the built artifacts |
| test/run               | No        | Test script for the builder image                            |
| test/test-app          | Yes       | Test application source code                                 |

The builder image is created from the Dockerfile, so the Dockerfile will contain all the packages and libraries needed to compile/build/etc the source code.  The Dockerfile will also need to copy the `s2i/bin/*` and `test/*` files into the resulting image to allow Source To Image to use them.

The `s2i/bin/assemble` script contains the logic to do build the application or install it's dependencies.  For example, if the builder images was for Python applications, the assemble script would probably call `pip install` to install the dependencies from the `requirements.txt` file.  For this Golang builder, the assemble script will run `go get`, among other things.

The `s2i/bin/run` script is what is set as the Docker `CMD` or `ENTRYPOINT` in the Dockerfile, and is responsible for starting the application when the application image is run.  In most cases this script is required, because the resulting image from the Source to Image build is what is run.  For the Golang builder, it is not strictly necessary, as we will be taking it a step further, but it is helpful for testing your application, so it is worth including.

The `s2i/bin/save-artifacts` script takes all the artifacts required for the application to run and streams them through the `tar` command to `stdout`.  This allows the builder image to do incremental builds, or, as with the this Golang builder, allows us to extract the compiled binary so it can be included in a subsequent build.

These script files can be written in whatever language you like, as long as they can be executed in the container built from the Dockerfile.

__Note:__ The `test/test-app` file is not really required.  If using the `s2i create` command to scaffold a new Source to Image builder, some tests are setup for you, but they are not necessary.  The `run` script is required for most Source to Image builders, but for the Golang builder image we are creating here, it is just a convenience.

You also need the Source-to-Image software itself to build the runtime or application images, but it is not necessarily required for it to be installed on your local system.  You could create your entire build pipeline in OKD or OpenShift Container Platform and do all your builds there.  It is just easier to develop and test images with the software installed locally.

Grab the [latest release of Source to Image](https://github.com/openshift/source-to-image/releases) for your platform, or install it with your distribution's package manager (eg: `dnf install s2i`).


## Golang s2i files

The Golang builder image is no exception; this project will need a `Dockerfile` to create the builder, an `assemble` script with the logic to compile a Go application, a `run` script to launch the app (for convenience only), and a `save-artifacts` script to save the compiled application.

Lets take a look at these required files, as we will use them for the builder image.

_Note:_ All of the files referenced here are available from the associated Github repository: [https://github.com/clcollins/golang-s2i](https://github.com/clcollins/golang-s2i)

**Dockerfile**

* assemble
* run
* save-artifacts

## Building the Builder Image

`docker build -t golang-builder .`

## Building the application image

### GoHelloWorld
Lets meet our app
* Tests?

### Build it
```
# s2i build <repo> <builder-image> <resulting-image>
s2i build . golang-builder go-hello-world
```

### test the app
But oh! We did that in the build!

### run the app

```
$ docker run go-hello-world:1.0
Hello World!
```

  OH SO BIG!
  `docker images |grep go-hello-world`
  PORTS and Configs and Cruft, oh-my!

## Build a runtime image
We can do better - a RUNTIME image

* this is why save-artifacts

### Runtime files
* Generate a dockerfile

```
FROM scratch
LABEL maintainer 'Chris Collins <collins.christopher@gmail.com>'

COPY app /app

ENTRYPOINT ["/app"]
```

Why `ENTRYPOINT` and not `CMD`?
  Nothing else is in the image, so you couldn't run it anyway.

Another Gotcha:

In the APP dockerfile, specifying ENTRYPOINT/CMD without [] will result in:

```
container_linux.go:247: starting container process caused "exec: \"/bin/sh\": stat /bin/sh: no such file or directory"
/usr/bin/docker-current: Error response from daemon: oci runtime error: container_linux.go:247: starting container process caused "exec: \"/bin/sh\": stat /bin/sh: no such file or directory"
```

as it is trying to run a shell.  Link to Docker ENTRYPOINT/CMD example


### Copy out the app

`docker run <your built app image> /usr/libexec/s2i/save-artifacts | tar -xf -`

### About streaming with tar

Opine some stuff

### Building the runtime image

`docker build -f Dockerfile-runtime -t go-hello-world:slim .`

It's smaller!  By a lot!


## Bootstrapping s2i with s2i create
* the Makefile rocks

make
make test?
make appimage
make test-appimage
make save
make runtime


## Implement with OKD/OpenShift BuildConfig
Do all this automagicaly with OKD
OKD Chained Builds

* buildConfig.yaml

[https://docs.okd.io/latest/dev_guide/builds/advanced_build_operations.html#dev-guide-chaining-builds](https://github.com/openshift/source-to-image/releases)

TODO: Conclusion
