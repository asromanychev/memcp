# syntax=docker/dockerfile:1.7

ARG RUBY_VERSION=3.3.0

FROM ruby:${RUBY_VERSION}-alpine AS base

ENV APP_ROOT=/rails \
    BUNDLE_APP_CONFIG=/bundle \
    BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    GEM_HOME=/bundle \
    PATH=/bundle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    RAILS_ENV=production \
    RACK_ENV=production

RUN apk add --no-cache \
      bash \
      build-base \
      curl \
      git \
      libffi-dev \
      libxml2-dev \
      libxslt-dev \
      nodejs \
      postgresql-client \
      postgresql-dev \
      tzdata \
      yaml-dev

WORKDIR ${APP_ROOT}

FROM base AS dependencies

COPY Gemfile Gemfile.lock ./
RUN bundle config set deployment 'true' && \
    bundle config set without 'development' && \
    bundle config set path "${BUNDLE_PATH}" && \
    bundle install --jobs="$(nproc)" --retry=3

FROM dependencies AS builder

ENV RAILS_ENV=production

COPY . .

# Precompile bootsnap cache when available; ignore if gem missing.
RUN if bundle exec ruby -e "require 'bootsnap'"; then \
      bundle exec bootsnap precompile app/ lib/; \
    fi

FROM base AS production

COPY --from=builder ${BUNDLE_PATH} ${BUNDLE_PATH}
COPY --from=builder ${APP_ROOT} ${APP_ROOT}

RUN addgroup -S rails && adduser -S rails -G rails

USER rails

EXPOSE 3000

ENTRYPOINT ["./bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
