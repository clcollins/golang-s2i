# golang-builder
FROM golang:1.12
LABEL maintainer "Chris Collins <collins.christopher@gmail.com>"

ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOCACHE=/tmp \
    STI_SCRIPTS_PATH=/usr/libexec/s2i \
    SOURCE_DIR=/go/src/app

LABEL io.k8s.description="Builder image for compiling and testing Go applications" \
      io.k8s.display-name="golang-builder}" \
      io.openshift.s2i.scripts-url=image://${STI_SCRIPTS_PATH}
      
# Copy the s2i scripts into the golang image
# These scripts describe how to build & run the application, and extract artifacts 
# for downstream builds
COPY ./s2i/bin/ ${STI_SCRIPTS_PATH}

# The $SOURCE_DIR is dependent on the upstream golang image, based on the 
# $GOPATH, etc. variable set there
#
# Allow random UIDs to write to the $SOURCE_DIR (for OKD/OpenShift)
RUN mkdir -p $SOURCE_DIR \
      && chmod 0777 $SOURCE_DIR

WORKDIR $SOURCE_DIR

# Drop root (as is tradition)
USER 1001


CMD ["/usr/libexec/s2i/usage"]
