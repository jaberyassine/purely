FROM node:22-alpine AS build
WORKDIR /build
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:stable-alpine
RUN mkdir -p /var/cache/nginx /var/run /etc/nginx/tls && chown -R 101:101 /var/cache/nginx /var/run /etc/nginx/tls /usr/share/nginx/html
COPY --from=build /build/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
USER 101:101
EXPOSE 8080 8443
ENTRYPOINT ["nginx","-g","daemon off;"]
