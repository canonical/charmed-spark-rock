# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.


# ---------------------------------------------------------------------------
# This is an OCI image for Kyuubi K8s charm.
#
# It is an open source, end-to-end, production ready data platform on top of
# cloud native technologies.
# ---------------------------------------------------------------------------

    ARG KYUUBI_ARTIFACT="https://dlcdn.apache.org/kyuubi/kyuubi-1.10.1/apache-kyuubi-1.10.1-bin.tgz"
    ARG KYUUBI_512_CHECKSUM="9b565bb7c628a50ecd394741eedb9a5154590709603e26f81de88ffd3b5256603215e71160de61360b8f2e2842116026c2f9ed3a60a8f0356388e3dd2c00b84c"
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
