# Writing your own Golang Builder with Source-to-Image

[![Docker Repository on Quay](https://quay.io/repository/clcollins/golang-builder/status "Docker Repository on Quay")](https://quay.io/repository/clcollins/golang-builder)

[Source To Image](https://github.com/openshift/source-to-image) is an excellent tool for building container images for applications in a fast, flexible and _reproducible_ way.  Source to Image (s2i or sti) takes a base, "builder" image with all the libraries and build tools needed to compile an application (as with a Golang app) or install dependencies (like Python's Pip, or Ruby's Bundler) and a set of scripts in a well-known location that are used to build, test and run the application.  Once the builder image is created, Source to Image can take code from a repository, inject it into the build image, compile or install dependencies, and generate an application image with the final application ready to go.

Source to Image makes it easy to reproduce consistent images and allows developers to focus on their applications rather than Docker images and containers, and since the build environment is created ahead of time, builds only take as long as the application takes to compile or configure.

The real beauty of source to image in my opinion, though, is the ability to use builder images as templates, so that similar applications with similar configurations can be deployed without managing Dockerfiles and Docker builds for every app - providing identical, and reproducible, environments for similar applications.

Many official Source to Image builder images already exist (eg. [Python s2i](https://github.com/sclorg/s2i-python-container), [Ruby s2i](https://github.com/sclorg/s2i-ruby-container)), but it's also simple to make your own to suit your needs.

For this tutorial, we'll build a Golang Source to Image builder image, and use it to build a test "Hello World" application.


## What do you need for s2i?

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
tar file; you must be careful to prevent text or other content being sent.  Pipe all output other than that of `tar` to `/dev/null` to ensure the tar archive is not corrupted with other data.

_ProTip:_ If you attempt to stream the contents of the tar file out of the container manually by running the `save-artifacts` script as the command for the container, you **MUST NOT** use the `-i` or `-t` arguments, because `tar` refuses to stream output to the the pseudo-terminal.

In our case, because the builder is compiling a single binary, this script is also just two lines, and has no other output to worry about:

```
#!/bin/sh -e
tar cf - app
```


## Building the Builder Image

That's it!  Once the Dockerfile and s2i scripts are ready, the Golang builder image can be created with the `docker build` command:

`docker build -t golang-builder .`

This will result in a builder image named `golang-builder`.


## Building the application image

The `golang-builder` image is not much use without an application to build.  For this exercise, we will build a simple hello-world application.


### GoHelloWorld

Lets meet our test app, [GoHelloWorld](https://github.com/clcollins/goHelloWorld.git).  There are to important (for this exercise) important files in this repository:

```
// goHelloWorld.go
package main

import "fmt"

func main() {
  fmt.Println("Hello World!")
}
```

This is a very basic app, but it will work fine for testing the builder image.  We also have a basic test for GoHelloWorld:

```
// goHelloWorld_test.go
package main

import "testing"

func TestMain(t *testing.T) {
  t.Log("Hello World!")
}
```


### Build the application image

Building the application image entails running the `s2i build` command, with arguments for the repository containing the code to build (or '.' to build with code from the current directory), the name of the builder image to use, and the name of the resulting application image to create.

```
$ s2i build https://github.com/clcollins/goHelloWorld.git golang-builder go-hello-world
```

To build from a local repository on your filesystem, replace the git URL with '.', for example:

```
$ s2i build . golang-builder go-hello-world
```

_Note:_  If you have initialized a git repository in the current directory, s2i will fetch the code from the repository URL rather than using the local code.  This results in local, uncommitted changes not being used when building the image.  Directories that are not git initialized repositories behave as expected.


### Run the application image

Once the application image has been built, it can be tested by running it with the Docker command.  Source to Image has replaced the `CMD` in the image with the `run` script created earlier, so it will execute the "/go/src/app/app" binary created during the build process.

```
$ docker run go-hello-world
Hello World!
```

Success!  We now have a compiled Go application inside of a Docker image, created by passing the contents of a git repo to Source to Image, and without the need to have a special Dockerfile for our application.

The application image just built includes not only the application, but its source code, test code, the Source to Image scripts, Golang libraries, _and much of the Debian Linux distribution_ (because the Golang image is based on the Debian base image).  The resulting image is not small:

```
$ docker images | grep go-hello-world
go-hello-world      latest      75a70c79a12f      4 minutes ago      789 MB
```

For applications written in Ruby or Python, this would not be a big deal; for interpreted languages with linked libraries, the source code and operating system are necessary.  For these kinds of applications, you could stop here with your Source to Image builds.  Since the resulting application image would be the same image used to run the production app, ports, volumes, and environment variables needed to run could be added to the Dockerfile for the builder image.  For example, to use the builder image to create application images for Rails apps running Puma, `PORT 3000` could be set in the builder Dockerfile and inherited in all the images generated from it.

But for the Go app, we can do better.


## Build a runtime image

Since our builder image created a statically compiled Go binary with our application, we can create a final "runtime" image containing _only_ the binary, and none of the other cruft.

Once the application image is created, the compiled goHelloWorld app can be extracted and put into a new, empty image using the `save-artifacts` script.

### Runtime files

To create the runtime image, only the application binary and a Dockerfile are required.

**Application binary**

Inside of the application image, the `save-artifacts` script is written to stream a tar archive of the app binary to stdout.  You can check the files included in the tar archive created by `save-artifacts` with the `-vt` flags for `tar`:

```
$ docker run go-hello-world /usr/libexec/s2i/save-artifacts | tar -tvf -
-rwxr-xr-x 1001/root   1997502 2019-05-03 18:20 app
```

If this results in errors along the lines of "This does not appear to be a tar archive", your `save-artifacts` script is probably outputting other data in addition to the `tar` stream, as mentioned above.  Make sure to suppress all output other than the `tar` stream itself.

If everything looks OK, use `save-artifacts` to copy the binary out of the application image:

```
$ docker run go-hello-world /usr/libexec/s2i/save-artifacts | tar -xf -
```

This will copy the `app` file into your current directory, ready to be added to its own image.

**Dockerfile**

The Dockerfile is extremely simple - only three lines.  The `FROM scratch` source denotes that an empty, blank parent image is used.  The rest of the Dockerfile just specifies copying binary into `/app` in the image, and using that binary as the image `ENTRYPOINT`.

```
FROM scratch
COPY app /app
ENTRYPOINT ["/app"]
```

Save this Dockerfile as `Dockerfile-runtime`.

Why `ENTRYPOINT` and not `CMD`?  You could do either, but since there is nothing else in the image - no filesystem, no shell - you would be unable to run anything else, anyway.


### Building the runtime image

With the Dockerfile and binary ready to go, build the new runtime image:

```
$ docker build -f Dockerfile-runtime -t go-hello-world:slim .
```

The new runtime image is considerably smaller - just 2MB!

```
$ docker images | grep -e 'go-hello-world *slim'
go-hello-world      slim      4bd091c43816      3 minutes ago     2 MB
```

Test that it is still working as expected with `docker run`:

```
$ docker run go-hello-world:slim
Hello World!
```


## Bootstrapping s2i with s2i create

The `s2i` command has a sub-command to help you scaffold all the files you might need for a Source to Image build - `s2i create`

Using the `s2i create` command, we can generate a new project, creatively named "go-hello-world-2" in the `./ghw2` directory:

```
$ s2i create go-hello-world-2 ./ghw2
$ ls ./ghw2/
Dockerfile  Makefile  README.md  s2i  test
```

The create sub-command creates a placeholder Dockerfile, a README.md with information about how to use Source to Image, some example s2i scripts, a basic test framework, and a Makefile.  In particular, the Makefile is a great way to automate building and testing your Source to Image builder image.  Out of the box, just running `make` will build your image, and it can be extended to do more.   For example, you could add steps to build a base application image, or generate a runtime Dockerfile.


## Conclusion

In this tutorial, we have learned how to use Source To Image to build a custom Golang builder image, create an application image using `s2i build` and how to extract the application binary to create a super-slim runtime image.

In part two of this series, we will look at how to use the builder image we created with [OKD](https://okd.io), to automatically deploy our Golang apps with buildCongfigs, imageStreams, and deploymentConfigs.
