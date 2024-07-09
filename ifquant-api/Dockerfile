FROM php:8.0-apache
COPY conf/ifquant.ini /usr/local/etc/php/conf.d/ifquant.ini
RUN a2enmod headers \
    && sed -ri -e 's/^([ \t]*)(<\/VirtualHost>)/\1\tHeader set Access-Control-Allow-Origin "*"\n\1\2/g' /etc/apache2/sites-available/*.conf

RUN apt-get update \
	&& apt-get upgrade -y \
	&& apt-get install -y --no-install-recommends \
  nano \
	vim \
	ghostscript \
	imagemagick \
	sqlite3 
#RUN sed -ri -e 's/^([ \t]*)(<\/policymap>)/\1\t<policy domain="coder" rights="read | write" pattern="PDF" \/>\n\1\2/g' /etc/ImageMagick-6/policy.xml
RUN sed -i_bak 's/rights="none" pattern="PDF"/rights="read | write" pattern="PDF"/' /etc/ImageMagick-6/policy.xml
# make sure custom log directories exist
RUN mkdir /usr/local/log; \
    mkdir /usr/local/log/apache2; \
    mkdir /usr/local/log/php; \
    chmod -R ug+w /usr/local/log
# Configure apache mods
RUN a2enmod rewrite 

# Add ServerName parameter
RUN echo "ServerName localhost" | tee /etc/apache2/conf-available/servername.conf
RUN a2enconf servername		

	# Manually set up the apache environment variables
ENV APACHE_RUN_USER www-data
ENV APACHE_RUN_GROUP www-data
ENV APACHE_LOG_DIR /usr/local/log/apache2
ENV TERM xterm
# CMD ['cron','-f']