# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.


# ---------------------------------------------------------------------------
# This is an OCI image for Kyuubi K8s charm.
#
# It is an open source, end-to-end, production ready data platform on top of
# cloud native technologies.
# ---------------------------------------------------------------------------

    ARG KYUUBI_ARTIFACT="https://dlcdn.apache.org/kyuubi/kyuubi-1.9.3/apache-kyuubi-1.9.3-bin.tgz"
    ARG HIVE_ARTIFACT="https://archive.apache.org/dist/hive/hive-2.3.10/apache-hive-2.3.10-bin.tar.gz"
    ARG HIVE_256_CHECKSUM="f61349296582415090738ac812de026f3b54253a256c3ed2b2bb3ffe7377fd98"
    ARG HIVE_TARFILE="hive.tar.gz"
    ARG KYUUBI_512_CHECKSUM="4799abe24dbf624d8c6bbf84602e4c9d45ec5b8544f1d02b05b25489d2b57955b2759041bd88d7cce2697403fc4b2fbb5e27912811c0c3c5559bb0860f18e96e"
    ARG KYUUBI_TARFILE="kyuubi.tar.tgz"
    ARG BASE_IMAGE

# --------------------------------------------------------------------------
# Temporary stage to download and extract Kyuubi
# --------------------------------------------------------------------------

    FROM alpine:latest AS downloader

    ARG KYUUBI_ARTIFACT
    ARG HIVE_ARTIFACT
    ARG KYUUBI_512_CHECKSUM
    ARG HIVE_256_CHECKSUM
    ARG KYUUBI_TARFILE
    ARG HIVE_TARFILE

    # Install wget and tar in the temporary image
    RUN apk add --no-cache wget tar

    # Download and verify Kyuubi
    RUN wget -O $KYUUBI_TARFILE $KYUUBI_ARTIFACT
    RUN echo "$KYUUBI_512_CHECKSUM  $KYUUBI_TARFILE" | sha512sum -c -

    # Download and verify Hive
    RUN wget -O $HIVE_TARFILE $HIVE_ARTIFACT
    RUN echo "$HIVE_256_CHECKSUM  $HIVE_TARFILE" | sha256sum -c -

    # Create the target directory and extract the tarball for Kyuubi
    RUN mkdir -p /opt/kyuubi && \
        tar -xzvf $KYUUBI_TARFILE -C /opt/kyuubi --strip-components=1

    # Create the target directory and extract the tarball for Hive
    RUN mkdir -p /opt/hive && \
        tar -xzvf $HIVE_TARFILE -C /opt/hive --strip-components=1

# --------------------------------------------------------------------------
# Final stage 
# --------------------------------------------------------------------------

    FROM $BASE_IMAGE

    ARG BASE_IMAGE

    USER root

    # Copy the extracted Kyuubi files from the temporary stage
    COPY --from=downloader /opt/kyuubi /opt/kyuubi

    # Copy the extracted Hive files from the temporary stage
    COPY --from=downloader /opt/hive/scripts/metastore/upgrade/postgres /opt/hive/scripts/metastore/upgrade/postgres

    # Copy local files to the container
    COPY ./bin/kyuubi.sh /opt/pebble/kyuubi.sh
    RUN chown _daemon_:_daemon_ /opt/pebble/kyuubi.sh

    # Copy hive schematool to the image
    COPY ./bin/schematool.sh /opt/hive/bin/schematool.sh

    # Copy pebble layers
    COPY ./pebble/layers.yaml /var/lib/pebble/default/layers/002-charmed-kyuubi.yaml

    # Set appropriate permissions
    RUN chown -R _daemon_:_daemon_ /opt/kyuubi/ && \
        chmod -R 750 /opt/kyuubi

    USER _daemon_

    # Provide Default Entrypoint for Pebble
    ENTRYPOINT [ "/bin/pebble", "enter", "--verbose", "--args", "sparkd" ]