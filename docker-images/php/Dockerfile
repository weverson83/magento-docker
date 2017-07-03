FROM php:5.6-fpm

# Install
RUN buildDeps=" \
        libpng12-dev \
        libjpeg-dev \
        libmcrypt-dev \
        libxml2-dev \
        freetype* \
        libicu-dev \
        g++ \
        golang-go \
        git-core \
        libmemcached-dev \
    "; \
    set -x \
    && apt-get update \
    && apt-get install -y $buildDeps --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

### Install Mailhog
ENV GOPATH /tmp
RUN cd /tmp
RUN go get github.com/mailhog/mhsendmail
RUN cd /tmp/src/github.com/mailhog/mhsendmail/ && go build
RUN cp /tmp/src/github.com/mailhog/mhsendmail/mhsendmail /usr/local/bin

RUN docker-php-ext-configure \
    gd --with-png-dir=/usr --with-jpeg-dir=/usr --with-freetype-dir \
    && docker-php-ext-install \
    gd \
    mbstring \
    mysqli \
    mcrypt \
    pdo_mysql \
    soap \
    zip \
    intl \
    && pecl install memcached-2.2.0 \
    && pecl install lzf \
    && docker-php-ext-enable memcached lzf \
    && cd /tmp/ && git clone https://github.com/derickr/xdebug.git \
    && cd xdebug && git checkout tags/XDEBUG_2_2_2 \
    && phpize && ./configure --enable-xdebug && make \
    && mkdir /usr/lib/php/ && cp modules/xdebug.so /usr/lib/php/xdebug.so \
    && touch /usr/local/etc/php/ext-xdebug.ini \
    && rm -r /tmp/xdebug

RUN curl -L -o /tmp/redis.tar.gz https://github.com/phpredis/phpredis/archive/2.2.7.tar.gz \
    && tar xfz /tmp/redis.tar.gz \
    && rm -r /tmp/redis.tar.gz \
    && mkdir /usr/src/php \
    && mkdir /usr/src/php/ext \
    && mv phpredis-2.2.7 /usr/src/php/ext/redis \
    && docker-php-ext-install redis

# Configure
COPY php.ini /usr/local/etc/php/php.ini
COPY php-fpm.conf /usr/local/etc/
COPY ext-xdebug.ini /usr/local/etc/php/conf.d/ext-xdebug.ini

# Make sure the volume mount point is empty
RUN rm -rf /var/www/html/*