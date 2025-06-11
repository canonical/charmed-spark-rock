# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.


# ---------------------------------------------------------------------------
# This is an OCI image for Kyuubi K8s charm.
#
# It is an open source, end-to-end, production ready data platform on top of
# cloud native technologies.
# ---------------------------------------------------------------------------

    ARG KYUUBI_ARTIFACT="https://github.com/canonical/central-uploader/releases/download/kyuubi-1.10.2-ubuntu0/kyuubi-1.10.2-ubuntu0-20250610141741.tgz"
    ARG HIVE_ARTIFACT="https://archive.apache.org/dist/hive/hive-2.3.10/apache-hive-2.3.10-bin.tar.gz"
    ARG HIVE_256_CHECKSUM="f61349296582415090738ac812de026f3b54253a256c3ed2b2bb3ffe7377fd98"
    ARG HIVE_TARFILE="hive.tar.gz"
    ARG KYUUBI_512_CHECKSUM="59299a27f540d8abc30ec29910a872ab89fe9c5a6af186101c4344358ddce3714180544a896cbf415a0c262c32a23f62dc3e9d14f0593e081975de9922998d9f"
    ARG KYUUBI_TARFILE="kyuubi.tar.tgz"
    ARG BASE_IMAGE

# --------------------------------------------------------------------------
# Temporary stage to download and extract Kyuubi
# --------------------------------------------------------------------------

    FROM alpine:latest AS downloader

    ARG KYUUBI_ARTIFACT
    ARG KYUUBI_512_CHECKSUM
    ARG KYUUBI_TARFILE

    # Install wget and tar in the temporary image
    RUN apk add --no-cache wget tar

    # Download and verify Kyuubi
    RUN wget -O $KYUUBI_TARFILE $KYUUBI_ARTIFACT
    RUN echo "$KYUUBI_512_CHECKSUM  $KYUUBI_TARFILE" | sha512sum -c -

    # Create the target directory and extract the tarball for kyuubi
    RUN mkdir -p /opt/kyuubi && \
        tar -xzvf $KYUUBI_TARFILE -C /opt/kyuubi --strip-components=1

# --------------------------------------------------------------------------
# Final stage 
# --------------------------------------------------------------------------

    FROM $BASE_IMAGE

    ARG BASE_IMAGE

    USER root

    # Copy the extracted Kyuubi files from the temporary stage
    COPY --from=downloader /opt/kyuubi /opt/kyuubi

    # Copy local files to the container
    COPY ./bin/kyuubi.sh /opt/pebble/kyuubi.sh
    RUN chown _daemon_:_daemon_ /opt/pebble/kyuubi.sh

    # Copy pebble layers
    COPY ./pebble/layers.yaml /var/lib/pebble/default/layers/002-charmed-kyuubi.yaml

    # Copy PostgreSQL dependencies
    RUN cp /opt/kyuubi/jars/postgresql* /opt/spark/jars

    # Set appropriate permissions
    RUN chown -R _daemon_:_daemon_ /opt/kyuubi/ && \
        chmod -R 750 /opt/kyuubi

    USER _daemon_

    # Provide Default Entrypoint for Pebble
    ENTRYPOINT [ "/bin/pebble", "enter", "--verbose", "--args", "sparkd" ]
