FROM nginx
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf
COPY server.crt /tmp/server.crt
COPY server.key /tmp/server.key
