#####################################
# BASE BUILDER IMAGE
#####################################
FROM ruby:alpine3.21 AS builder

# Install dependencies for building Jekyll
RUN apk add --no-cache build-base

WORKDIR /app

# Install all needed gems
RUN gem install bundler \
    jekyll \
    jekyll-sitemap \
    rouge \
    redcarpet \
    jekyll-paginate \
    jekyll-tagging \
    jekyll-tagging-related_posts \
    jekyll-scholar \
    unicode

