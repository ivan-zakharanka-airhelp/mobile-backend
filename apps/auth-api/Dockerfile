# Build context: repo root (mobile-backend/)
FROM node:22-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
COPY packages/database/package.json ./packages/database/
COPY apps/auth-api/package.json ./apps/auth-api/
RUN npm ci

COPY packages/database/ ./packages/database/
COPY apps/auth-api/ ./apps/auth-api/
RUN npm run generate -w @mobile-backend/database
RUN npm run build -w @mobile-backend/database
RUN npm run build -w @mobile-backend/auth-api

FROM node:22-alpine AS production
WORKDIR /app
ENV NODE_ENV=production

COPY package.json package-lock.json ./
COPY packages/database/package.json ./packages/database/
COPY apps/auth-api/package.json ./apps/auth-api/
RUN npm ci --omit=dev

COPY --from=build /app/packages/database/dist ./packages/database/dist
COPY --from=build /app/apps/auth-api/dist ./apps/auth-api/dist
COPY --from=build /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=build /app/packages/database/prisma ./packages/database/prisma

EXPOSE 3000
CMD ["node", "apps/auth-api/dist/main.js"]
