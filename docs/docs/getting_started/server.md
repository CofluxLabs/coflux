# 2. Running the server

The Coflux server can be run as a Docker container. Data will be stored in the working directory.

From a suitable directory, **run the following command**:

```bash
docker run \
  --pull always \
  -p 7777:7777 \
  -v $(pwd):/data \
  ghcr.io/cofluxlabs/coflux
```

**Open up the web UI** at http://localhost:7777.

## Setting up a project

Before we can connect an agent, we need to create a Coflux project and an environment.

**Create a project and an environment using the web UI**, and **take note of the project ID and environment name**.

Next, we can start an agent...
