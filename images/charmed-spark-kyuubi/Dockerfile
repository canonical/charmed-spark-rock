# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.


# ---------------------------------------------------------------------------
# This is an OCI image for Kyuubi K8s charm.
#
# It is an open source, end-to-end, production ready data platform on top of
# cloud native technologies.
# ---------------------------------------------------------------------------

    ARG KYUUBI_ARTIFACT="https://github.com/canonical/central-uploader/releases/download/kyuubi-1.10.2-ubuntu2/kyuubi-1.10.2-ubuntu2-20250806154859.tgz"
    ARG HIVE_ARTIFACT="https://archive.apache.org/dist/hive/hive-2.3.10/apache-hive-2.3.10-bin.tar.gz"
    ARG HIVE_256_CHECKSUM="f61349296582415090738ac812de026f3b54253a256c3ed2b2bb3ffe7377fd98"
    ARG HIVE_TARFILE="hive.tar.gz"
    ARG KYUUBI_512_CHECKSUM="97c4a9959b9ac532ff2009a333303f99e10a5c04daff2ea2ec65e4338f91b2644f063560019e13ea65383a8755dfdb1fc016316a2dee5ff48fc4602c97ddae98"
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

    # Copy PostgreSQL dependencies
    RUN cp /opt/kyuubi/jars/postgresql* /opt/spark/jars

    # Set appropriate permissions
    RUN chown -R _daemon_:_daemon_ /opt/kyuubi/ && \
        chmod -R 750 /opt/kyuubi

    USER _daemon_

    # Provide Default Entrypoint for Pebble
    ENTRYPOINT [ "/bin/pebble", "enter", "--verbose", "--args", "sparkd" ]
