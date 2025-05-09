# Use an official Node.js runtime
FROM node:18-slim

# Install OS dependencies (for NVIDIA smi, Docker socket access, etc.)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         curl \
         gnupg2 \
         ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy package.json & package-lock.json
COPY package*.json ./

# Install JavaScript dependencies
RUN npm install --production

# Copy application code
COPY server.js ./
COPY public ./public

# Expose port
ENV PORT=3000
EXPOSE 3000

# Use NVIDIA runtime entrypoint (if running with --gpus)
# and ensure Docker socket is available for Dockerode
CMD ["node", "server.js"]
