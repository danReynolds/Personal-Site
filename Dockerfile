# Base Ruby layer
FROM ruby:latest

# Set the working directory to /app
RUN mkdir /app
WORKDIR /app

# Install all needed gems
RUN gem install bundler sshkit rake jekyll jekyll-sitemap rouge redcarpet jekyll-paginate jekyll-tagging jekyll-tagging-related_posts jekyll-scholar unicode

# Start server
CMD ["jekyll", "serve", "--host", "0.0.0.0"]
