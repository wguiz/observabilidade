FROM node:22-alpine

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.js ./
COPY src ./src
COPY public ./public

ENV PORT=3000
EXPOSE 3000

# Não roda como root (lição da aula 13 / Trivy)
USER node

CMD ["node", "server.js"]
