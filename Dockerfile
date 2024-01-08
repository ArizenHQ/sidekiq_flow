# Base Stage
#
# This stage is responsible for setting up the base image from which all other stages will be built.
# It starts from a clean Ubuntu image and sets up a basic environment for the application.
# It creates necessary directories, sets up environment variables, and configures the shell prompt.
# It also sets up the versions for Ruby, Node.js, Yarn, and other dependencies that will be installed in the builder stage.
FROM ubuntu:focal AS base

RUN set -eux; \
  mkdir -p /usr/local/etc; \
  { \
  echo 'install: --no-document'; \
  echo 'update: --no-document'; \
  } >> /usr/local/etc/gemrc

ENV RUBY_VERSION 2.7.8
ENV RUBY_INSTALL_VERSION 0.9.1
ENV BUNDLE_VERSION 1.16.1
ENV GEM_VERSION 3.4.16
ENV NODE_MAJ 20

ENV APP_HOME /app
ENV LANG C.UTF-8
ENV DEBIAN_FRONTEND noninteractive

# Application runtime dependencies for gems
RUN apt-get clean && apt-get update -qq  \
  && apt-get install -yq --no-install-recommends \
  tzdata \
  libssl-dev

RUN echo "PS1='\u@\h:\w\$ '" >> /root/.bashrc

# install the smallest subset of gems possible
ENV BUNDLE_WITHOUT development:test:staging
ENV RAILS_ENV production
ENV RACK_ENV production
# install smallest subset of npms as possible
ENV NODE_ENV production

# TODO run checksum on downloaded files
# install ruby + bundler with builtime gem dependencies
RUN apt-get clean \
  && apt-get update -qq \
  && apt-get install -yq --no-install-recommends \
  build-essential \
  bison \
  ca-certificates \
  gpg \
  git \
  tzdata \
  wget \
  zlib1g-dev \
  && wget -O ruby-install-$RUBY_INSTALL_VERSION.tar.gz https://github.com/postmodern/ruby-install/archive/v$RUBY_INSTALL_VERSION.tar.gz \
  && tar -xzvf ruby-install-$RUBY_INSTALL_VERSION.tar.gz \
  && cd ruby-install-$RUBY_INSTALL_VERSION/ \
  && make install \
  && ruby-install --update \
  && ruby-install --system ruby $RUBY_VERSION \
  && gem update --system $GEM_VERSION \
  && gem install bundler -v $BUNDLE_VERSION --no-document

# install Nodejs
RUN apt-get update -qq \
  && apt-get install -yq --no-install-recommends gnupg \
  && mkdir /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJ}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && apt-get update -qq \
  && apt-get install -yq --no-install-recommends nodejs \


  # cleanup
  RUN apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && rm -rf /ruby-install-$RUBY_INSTALL_VERSION \
  && rm /ruby-install-$RUBY_INSTALL_VERSION.tar.gz \
  && rm /usr/local/bin/ruby-install \
  && rm -rf /usr/local/share/ruby-install \
  && rm -Rf /usr/local/src/ruby* \
  && rm -Rf /usr/local/share/ri \
  && rm -Rf /usr/local/share/doc/ruby*

WORKDIR $APP_HOME
COPY . $APP_HOME

RUN bundle install --with development \
  && rm -rf /usr/local/bundle/cache/*.gem

# Add source
COPY . $APP_HOME

# Save timestamp of image building
RUN date -u > BUILD_TIME
