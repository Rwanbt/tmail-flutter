ARG FLUTTER_VERSION=3.38.9

# The base images are pinned by digest: the tag alone lets the registry serve a
# different image on the next build, which would make the published artifact
# unreproducible. Update the digest deliberately, with the tag it belongs to.
FROM --platform=amd64 ghcr.io/instrumentisto/flutter:${FLUTTER_VERSION}@sha256:7d227ac458bbb5aca38ada779dc0bf983ad24deae8d2ef3ebf5b779915d1547d AS build-env

ARG SENTRY_AUTH_TOKEN
ARG SENTRY_ORG
ARG SENTRY_PROJECT
ARG SENTRY_URL
ARG SENTRY_RELEASE
ARG VCS_REF
ARG GITHUB_SHA

WORKDIR /app
COPY . .

ENV GITHUB_SHA=$GITHUB_SHA \
    SENTRY_ORG=$SENTRY_ORG \
    SENTRY_PROJECT=$SENTRY_PROJECT \
    SENTRY_URL=$SENTRY_URL \
    SENTRY_RELEASE=$SENTRY_RELEASE

RUN ./scripts/prebuild.sh && \
    SENTRY_AUTH_TOKEN=${SENTRY_AUTH_TOKEN:-} ./scripts/configure-sentry.sh && \
    flutter build web --release --source-maps --no-web-resources-cdn \
    --dart-define=SENTRY_RELEASE=$SENTRY_RELEASE \
    --dart-define=SENTRY_DIST=$GITHUB_SHA && \
    SENTRY_AUTH_TOKEN=${SENTRY_AUTH_TOKEN:-} ./scripts/run-sentry.sh

FROM nginx:alpine@sha256:060849a174666c53439dc7cecbf8f67e225c7cbfb1a44ca97915d9a172a81e6d
RUN apk add gzip
COPY --from=build-env /app/server/nginx.conf /etc/nginx
COPY --from=build-env /app/build/web /usr/share/nginx/html
EXPOSE 80
CMD gzip -k -r -f /usr/share/nginx/html/ && nginx -g 'daemon off;'