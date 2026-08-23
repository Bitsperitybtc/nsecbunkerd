FROM node:22-bullseye AS build

WORKDIR /app

# Copy package files and install dependencies
COPY package*.json ./
RUN npm install

# Copy application files
COPY . .

# Generate prisma client and build the application
RUN npx prisma generate
RUN npm run build

# Runtime stage
FROM node:22-bullseye AS runtime

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl && \
    rm -rf /var/lib/apt/lists/*

# Copy built files from the build stage
COPY --from=build /app .

# Install only runtime dependencies
RUN npm install --only=production

EXPOSE 3000

ENTRYPOINT [ "node", "./dist/index.js" ]
CMD ["start"]
