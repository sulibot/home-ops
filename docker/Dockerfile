FROM alpine:latest

# Install minimal dependencies (bash and curl)
RUN apk add --no-cache bash curl jq ca-certificates

# Copy the script
COPY update-node-label.sh /usr/local/bin/update-node-label.sh
RUN chmod +x /usr/local/bin/update-node-label.sh

# Run the script
CMD ["/usr/local/bin/update-node-label.sh"]
