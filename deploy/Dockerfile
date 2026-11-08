# Fleet backend image — build from the REPO ROOT:
#   docker build -f deploy/Dockerfile -t swat-fleet-backend .
FROM node:22-alpine
WORKDIR /app
COPY backend/package.json backend/package-lock.json ./
RUN npm ci --omit=dev
COPY backend/ ./
ENV PORT=8787
EXPOSE 8787
CMD ["node", "server.mjs"]
