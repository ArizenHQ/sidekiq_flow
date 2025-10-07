# Use the official Ruby image as a parent image
FROM ruby:3.2

# Set environment variables to avoid warnings during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install Node.js 20
RUN curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh \
    && bash nodesource_setup.sh \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* nodesource_setup.sh

# Set the working directory inside the container
WORKDIR /app

CMD ["tail", "-f", "/dev/null"]