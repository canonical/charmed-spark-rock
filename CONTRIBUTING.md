## Contributing and Developer guide

The steps outlined below are based on the assumption that you are building the ROCK with the Ubuntu Jammy (22.04).  If you are using another version of Ubuntu or another operating system, the process may be different.

### Clone Repository
```bash
git clone git@github.com:canonical/charmed-spark-rock.git
cd charmed-spark-rock
```

### Installing Prerequisites
```bash
sudo snap install rockcraft --edge
sudo snap install docker
sudo snap install lxd
sudo snap install yq
sudo snap install skopeo --edge --devmode
```

### Configuring Prerequisites
```bash
sudo usermod -aG docker $USER 
sudo lxd init --auto
```

In order for the group change to take effect, you can either open a new shell (i.e. `su - $USER`) or use the following

```bash
newgrp docker
sudo snap disable docker
sudo snap enable docker
```

### Build Rocks

> :warning: The image is currently built in a two-stage process: first the image is built using rockcraft and the resulting image is then patched (overriding the entrypoint) using a Dockerfile. The reason for this is that the feature needed for having a Spark compliant UX has yet to land in Rockcraft/Pebble.

The process is however streamlined by Makefile API, such that removing the patch will be transparent to the UX below.

Building and exporting is handled by `make` commands, e.g. 

```bash
make build
```

This will create a charmed image in your local Docker installation. If you have MicroK8s installed on your system (or you can install it by issuing `make microk8s`), you can also export this to the `MicroK8s` container registry:

```bash
make import TARGET=microk8s
```

### Integration testing

If you want to mock the image being published to the upstream container registry (useful for integration tests of other components in the Charmed Spark solution), use the following

```bash
make import TARGET=microk8s REPOSITORY=ghcr.io/canonical/
```

### Clean the environment

```bash
make clean
```

For further information about the `make` instructions, use `make help` or refer to the [Makefile](./Makefile).