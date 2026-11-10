FROM node:20-alpine
WORKDIR /app
COPY server.mjs core.mjs apns.mjs ./
ENV NODE_ENV=production PORT=8080 DATA_DIR=/data
EXPOSE 8080
CMD ["node", "server.mjs"]
