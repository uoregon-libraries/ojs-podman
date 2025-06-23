# PHP 8.1 is essential here - 8.2 and later give us problems
FROM php:8.1-apache

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    zip \
    unzip \
    libzip-dev \
    default-mysql-client \
    libmariadb-dev

# Install PHP extensions
RUN docker-php-ext-install pdo_mysql
RUN docker-php-ext-install mysqli
RUN docker-php-ext-install mbstring exif pcntl bcmath gd zip intl

# Grab the production package from the website before any custom stuff since
# this is one of the least likely steps to change
WORKDIR /var/www/html
RUN curl -L https://pkp.sfu.ca/ojs/download/ojs-3.4.0-9.tar.gz | tar -xz --strip-components=1
RUN find . -type d -exec chmod +rx {} \;

# Create and set permissions for dirs apache needs to write
VOLUME /var/local/ojs-files
VOLUME /var/www/html/cache
VOLUME /var/www/html/public
VOLUME /var/www/html/plugins
RUN mkdir -p /var/local/ojs-files /var/www/html/cache /var/www/html/public /var/www/html/plugins
RUN chown -R www-data:www-data /var/local/ojs-files /var/www/html/cache /var/www/html/public /var/www/html/plugins

# Create a dir for the config file which we can mount locally for editing
VOLUME /var/local/config
RUN mkdir -p /var/local/config
RUN chown -R www-data:www-data /var/local/config

# Set up Apache to allow overrides for our custom .htaccess file
RUN a2enmod rewrite
RUN a2enmod headers
RUN sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf

# Give PHP some sane config settings
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
RUN sed -i 's/upload_max_filesize\s*=.*$/upload_max_filesize = 1024M/' "$PHP_INI_DIR/php.ini"
RUN sed -i 's/post_max_size\s*=.*$/post_max_size = 1024M/' "$PHP_INI_DIR/php.ini"

# Now copy in all the files we customize
COPY config/htaccess /var/www/html/.htaccess
RUN chmod 644 .htaccess

# Set up our custom entrypoint and configgy stuff
COPY config/config-template.ini /config-template.ini
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/replace-vars.sh /replace-vars.sh
CMD ["apache2-foreground"]
ENTRYPOINT ["/entrypoint.sh"]
