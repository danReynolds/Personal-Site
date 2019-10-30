# Base Ruby layer
FROM ruby:2.7.0

# Set the working directory to /app
RUN mkdir /app
WORKDIR /app

# Install all needed gems
RUN gem install bundler sshkit rake jekyll jekyll-sitemap pygments.rb redcarpet jekyll-paginate jekyll-tagging jekyll-tagging-related_posts jekyll-scholar unicode

# Copy the current directory contents into the container at /app
ADD . /app

ENV JEKYLL_ENV production

# Start server
CMD ["jekyll", "serve", "--host", "0.0.0.0"]
