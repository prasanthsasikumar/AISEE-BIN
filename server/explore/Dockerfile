FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev
COPY lib.mjs server.mjs ./
ENV EXPLORE_LOG_DIR=/data
EXPOSE 8787
CMD ["node", "server.mjs"]
