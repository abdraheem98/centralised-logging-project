FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
COPY ../shared ./shared
EXPOSE 3010
CMD ["node", "index.js"]
