FROM node:22-alpine

# Install the official Smee client at a fixed version so the local webhook
# bridge can be rebuilt reproducibly instead of relying on a stale image.
RUN npm install --global smee-client@5.0.0 \
    && npm cache clean --force

# The relay only needs an outbound connection to Smee and access to Jenkins on
# the private Compose network, so it does not need to run as root.
USER node

ENTRYPOINT ["smee"]
