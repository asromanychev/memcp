# syntax=docker/dockerfile:1.7

FROM ruby:3.2.2-slim AS base

ENV APP_ROOT=/app \
    BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    GEM_HOME=/bundle \
    PATH=/bundle/bin:/usr/local/bundle/bin:$PATH \
    RAILS_ENV=development

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      postgresql-client \
      curl \
      git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR ${APP_ROOT}

ARG BUNDLER_VERSION=2.5.22
ENV BUNDLER_VERSION=${BUNDLER_VERSION}
RUN gem install bundler -v ${BUNDLER_VERSION}

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

ENTRYPOINT ["./bin/docker-entrypoint"]
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3001"]
