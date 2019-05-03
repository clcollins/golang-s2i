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

_Note:_ The `test/test-app` file is not really required.  If using the `s2i create` command to scaffold a new Source to Image builder, some tests are setup for you, but they are not necessary.  The `run` script is required for most Source to Image builders, but for the Golang builder image we are creating here, it is just a convenience.

You also need the Source-to-Image software itself to build the runtime or application images, but it is not necessarily required for it to be installed on your local system.  You could create your entire build pipeline in OKD or OpenShift Container Platform and do all your builds there.  It is just easier to develop and test images with the software installed locally.

Grab the [latest release of Source to Image](https://github.com/openshift/source-to-image/releases) for your platform, or install it with your distribution's package manager (eg: `dnf install s2i`).


## Golang s2i files

The Golang builder image is no exception; this project will need a `Dockerfile` to create the builder, an `assemble` script with the logic to compile a Go application, a `run` script to launch the app (for convenience only), and a `save-artifacts` script to save the compiled application.

Lets take a look at these required files, as we will use them for the builder image.

_Note:_ All of the files referenced here are available from the associated Github repository: [https://github.com/clcollins/golang-s2i](https://github.com/clcollins/golang-s2i)

**Dockerfile**

The Dockerfile is not actually very complicated. This builder image is going to use the upstream `golang:1.12` image as it's base, so we will not have to manage installing Go and setting up the environment.  A few environment variables also need to be set to allow Go applications to run in a container environment:

*   CGO_ENABLED=0
*   GOOS=linux

Kelsey Hightower talks more about why these are used in his article [Building Docker Images for Static Go Binaries](https://medium.com/@kelseyhightower/optimizing-docker-images-for-static-binaries-b5696e26eb07), so check that out if you want to know more.

The `GOCACHE=/tmp` environment variable also needs to be set in the Dockerfile to avoid write errors when running the build as a user other than root. This is an OKD/OpenShift convention to [support running containers with arbitrary UIDs](https://docs.okd.io/3.11/creating_images/guidelines.html#openshift-specific-guidelines), but it's also just good practice.  Check out Dan Walsh's article [Just say no to root (in containers)](https://opensource.com/article/18/3/just-say-no-root-containers) for more about why this is a good thing.

Then, set two more environment variables:

*   STI_SCRIPTS_PATH=/usr/libexec/s2i
*   SOURCE_DIR=/go/src/app

The first tells Source To Image where to find the scripts it needs to run, and the second is just for convenience, so our project is [DRY](https://en.wikipedia.org/wiki/Don%27t_repeat_yourself).

In the next section, ddd the Source to Image scripts (see below) to the builder image, and create and `chmod` the `$SOURCE_DIR`, where the scripts will compile the application, and set this as the `WORKDIR` so subsequent operations occur in that directory.

_Note:_ The `$SOURCE_DIR` is set to `/go/src/app` because the `$GOPATH` variable in the parent `golang:1.12` image is set to `/go`.

```
COPY ./s2i/bin/ ${STI_SCRIPTS_PATH}
RUN mkdir -p $SOURCE_DIR \
      && chmod 0777 $SOURCE_DIR
WORKDIR $SOURCE_DIR
```

Finally, set `USER 1001` to drop root privileges and assure support for random UIDs, as mentioned above, and set the `CMD` to the Source To Image `usage` script.

```
USER 1001
CMD ["/usr/libexec/s2i/usage"]
```

At this point your Dockerfile should look something like [the Dockerfile in the accompanying Github repository](https://github.com/clcollins/golang-s2i/blob/master/Dockerfile), with the exception of a few labels and comments.

**assemble**

The `assemble` script is what Source to Image uses to compile the Go app.

When s2i copies the application code into the builder image, it places it into `/tmp/src`.  Since the upstream image sets the `GOPATH` to `/go`, the assemble script just needs to copy to a directory in there - the `$SOURCE_DIR` we set earlier in the image.  Then it is just a matter of running `go get` and `go build`.  Because the `WORKDIR` was set to the same directory, the script will run from there.

```
#!/bin/bash -e

# Copy the src to the current directory - the WORKDIR/$SOURCE_DIR.
cp -Rf /tmp/src/. ./
go get -v
go build -v -o app -a -installsuffix cgo
```

The `go build` command is run with `-o app` build flag so the resulting binary will have a predictable name (specifically, "app").

That is all that is required in the `assemble` script, but `go test -v` can also be included at the end of the script to make sure the application passes all its code tests, so the image build will fail of any tests fail.

That's it for the `assemble` script.  [The assemble script in the Github repo](https://github.com/clcollins/golang-s2i/blob/master/s2i/bin/assemble) includes a few commands for copying artifacts from a previous build, but is otherwise the same.

**run**

The `run` script is used by s2i to execute the app if running a container from the resulting image build.  Appropriately, it is just two lines:

```
#!/bin/bash
exec app
```

_Note:_ If your application requires arguments, this script would need to be tweaked a little to pass those arguments.

**save-artifacts**

The `save-artifacts` image is not required for Source to Image.  It is used to re-use artifacts from a previous build (think: downloaded Pip packages or Ruby gems), and to do incremental builds, so it can make building images in development much faster.  The Golang builder image will use it a bit differently - to allow us to extract the compiled binary file so it can be included in a much slimmer runtime image (see below).

Source to Image expects the `save-artifacts` script to take all the files and dependencies for an application and stream them through the `tar` command to `stdout`, so they can be received on the other end and saved.  This is easy in theory, but can be tricky if you're not careful.  The contents streamed to `stdout` must include **ONLY** the contents of the
tar file; you must be careful to prevent text or other content being sent.

In our case, because the builder is compiling a single binary, this script is also just two lines, and has no other output to worry about:

```
#!/bin/sh -e
tar cf - app
```

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
