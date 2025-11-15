FROM php:8.3-cli-bookworm

# System deps for GD and Zip
RUN apt-get update && apt-get install -y --no-install-recommends \
      git unzip libzip-dev \
      libfreetype6-dev libjpeg62-turbo-dev libpng-dev \
  && docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install gd zip \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Dependencies
COPY composer.json /app/composer.json
RUN composer install --no-dev --prefer-dist --no-progress

# App
COPY api.php /app/api.php

EXPOSE 9000
CMD ["php", "-S", "0.0.0.0:9000", "api.php"]