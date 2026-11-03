# ---- Build stage ----
FROM node:22-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
# The app calls the API on a relative path (/api/v1), which nginx proxies to the backend
RUN npm run build

# ---- Runtime stage ----
# Floating tag so a rebuild picks up the latest patched nginx; apk upgrade pulls OS security fixes
FROM nginx:stable-alpine
RUN apk update && apk upgrade --no-cache
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY security-headers.inc /etc/nginx/conf.d/security-headers.inc
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80
