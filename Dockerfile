FROM node:22-alpine
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.28.2 --activate
COPY . .
RUN pnpm install --frozen-lockfile && pnpm build
ENV NODE_ENV=production
EXPOSE 3000
CMD ["pnpm", "--filter", "@groundtruth/field", "start"]
