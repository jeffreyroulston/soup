# Static build of the Soup web SPA served by nginx.
# NUXT_PUBLIC_* values are baked in at build time, so pass them as build args:
#   docker build --build-arg NUXT_PUBLIC_SOUP_IDENTITY_BASE_URL=http://nas.local:8787 \
#                --build-arg NUXT_PUBLIC_APP_ORIGIN=http://nas.local:3000 -t soup-web .

FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG NUXT_PUBLIC_SOUP_IDENTITY_BASE_URL=http://localhost:8787
ARG NUXT_PUBLIC_APP_ORIGIN=http://localhost:3000
ARG NUXT_PUBLIC_APP_NAME=Soup
ARG NUXT_PUBLIC_JELLYFIN_URL=
ARG NUXT_PUBLIC_MOCK=false
ENV NUXT_PUBLIC_SOUP_IDENTITY_BASE_URL=$NUXT_PUBLIC_SOUP_IDENTITY_BASE_URL \
    NUXT_PUBLIC_APP_ORIGIN=$NUXT_PUBLIC_APP_ORIGIN \
    NUXT_PUBLIC_APP_NAME=$NUXT_PUBLIC_APP_NAME \
    NUXT_PUBLIC_JELLYFIN_URL=$NUXT_PUBLIC_JELLYFIN_URL \
    NUXT_PUBLIC_MOCK=$NUXT_PUBLIC_MOCK
RUN npm run generate

FROM nginx:1.27-alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/.output/public /usr/share/nginx/html
EXPOSE 80
