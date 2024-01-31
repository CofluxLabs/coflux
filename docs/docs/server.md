# Running the server

The Coflux server can be run as a Docker container:

```bash
docker run \
  --pull always \
  -p 7777 \
  -v $(pwd):/data \
  ghcr.io/CofluxLabs/coflux
```

Open up the web UI at http://localhost:7777.

## Project setup

Before we can connect an agent, we need to create a Coflux project. Do this using the web UI, and take note of the project ID.

Next, we can start an agent...
