FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
COPY ../shared ./shared
EXPOSE 3004
CMD ["node", "index.js"]
