FROM ubuntu:latest

LABEL Description="This image is usable to setup a container including a custom Nginx build for efficient image serving and on-the-fly filterings such as watermark injection."
LABEL maintainer="xei <hosseinkhani@live.com>"

ARG OPENSSL_VERSION=1.1.1j
ARG ZLIB_VERSION=1.2.11
ARG PCRE_VERSION=8.44
ARG NGINX_VERSION=1.18.0

WORKDIR /tmp

# Install packages (add-apt-repository, wget, GCC Compiler, PERL, LIBATOMIC_OPS, LibGD, libxml2, Libxslt
# `DEBIAN_FRONTEND=noninteractive` is for running dpkg (behind apt-get) without interactive dialogue
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -q -y software-properties-common \
                                                          wget \
                                                          build-essential \
                                                          perl \
                                                          libperl-dev \
                                                          libgd3 \
                                                          libgd-dev \
                                                          libxml2 \
                                                          libxml2-dev \
                                                          libxslt1.1 \
                                                          libxslt1-dev
RUN add-apt-repository -y ppa:maxmind/ppa \
  && apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -q -y libgeoip1 \
                                                          libgeoip-dev \
                                                          geoip-bin

# Download and untar the latest version of `OpenSSL` for `TLS 1.3` and modern ciphers support
RUN wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz \
  && tar xzvf openssl-${OPENSSL_VERSION}.tar.gz

# Download and untar `ZLib` library for `deflate` and `gzip` support in HTTP responses
RUN wget https://www.zlib.net/zlib-${ZLIB_VERSION}.tar.gz \
  && tar xzvf zlib-${ZLIB_VERSION}.tar.gz

# Download and untar `PCRE 8.44` for regular expressions support in the `location` directive and the `ngx_http_rewrite_module` module
RUN wget https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VERSION}.tar.gz \
  && tar xzvf pcre-${PCRE_VERSION}.tar.gz

# Download and untar `Nginx` stable version
RUN wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
  && tar xzvf nginx-${NGINX_VERSION}.tar.gz

# Modify `ngx_http_image_filter_module` module in order to support watermark filter
COPY modules/ngx_http_image_filter_module.c nginx-${NGINX_VERSION}/src/http/modules/

# Configure, build and install Nginx
# Reference: http://nginx.org/en/docs/configure.html
RUN cd nginx-${NGINX_VERSION} \
  && ./configure --prefix=/usr/share/nginx \
                 --sbin-path=/usr/sbin/nginx \
                 --modules-path=/usr/lib/nginx/modules \
                 --conf-path=/etc/nginx/nginx.conf \
                 --error-log-path=/var/log/nginx/error.log \
                 --http-log-path=/var/log/nginx/access.log \
                 --pid-path=/run/nginx.pid \
                 --lock-path=/var/lock/nginx.lock \
                 --user=www-data \
                 --group=www-data \
                 --build=nginx-image-server \
                 --http-client-body-temp-path=/var/lib/nginx/body \
                 --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
                 --http-proxy-temp-path=/var/lib/nginx/proxy \
                 --http-scgi-temp-path=/var/lib/nginx/scgi \
                 --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
                 --with-openssl=../openssl-${OPENSSL_VERSION} \
                 --with-openssl-opt=enable-ec_nistp_64_gcc_128 \
                 --with-openssl-opt=no-nextprotoneg \
                 --with-openssl-opt=no-weak-ssl-ciphers \
                 --with-openssl-opt=no-ssl3 \
                 --with-pcre=../pcre-${PCRE_VERSION} \
                 --with-pcre-jit \
                 --with-zlib=../zlib-${ZLIB_VERSION} \
                 --with-compat \
                 --with-file-aio \
                 --with-threads \
                 --with-http_addition_module \
                 --with-http_auth_request_module \
                 --with-http_dav_module \
                 --with-http_flv_module \
                 --with-http_gunzip_module \
                 --with-http_gzip_static_module \
                 --with-http_mp4_module \
                 --with-http_image_filter_module \
                 --with-http_random_index_module \
                 --with-http_realip_module \
                 --with-http_slice_module \
                 --with-http_ssl_module \
                 --with-http_sub_module \
                 --with-http_stub_status_module \
                 --with-http_v2_module \
                 --with-http_secure_link_module \
                 --with-mail \
                 --with-mail_ssl_module \
                 --with-stream \
                 --with-stream_realip_module \
                 --with-stream_ssl_module \
                 --with-stream_ssl_preread_module \
                 --with-debug \
                 --with-cc-opt='-g -O2 -fPIE -fstack-protector-strong -Wformat -Werror=format-security -Wdate-time -D_FORTIFY_SOURCE=2' \
                 --with-ld-opt='-Wl,-Bsymbolic-functions -fPIE -pie -Wl,-z,relro -Wl,-z,now' \
  && make \
  && make install

# Print the Nginx version, compiler version and configure script parameters
RUN nginx -V

WORKDIR /etc/nginx
COPY nginx.conf .
COPY conf.d ./conf.d
COPY snippets ./snippets

# Inject `server_name` and `secret_key` into the template server block
ARG HOST_NAME=img.example.com
ARG SECRET_KEY=MY_SECRET_KEY
RUN sed -i "s/\${HOST_NAME}/$HOST_NAME/" conf.d/front-server.conf
RUN sed -i "s/\${SECRET_KEY}/$SECRET_KEY/" conf.d/front-server.conf

# Prevent error: nginx: [emerg] mkdir() "/var/lib/nginx/body" failed (2: No such file or directory)
RUN mkdir -p /var/lib/nginx
# Prevent error: nginx: [emerg] mkdir() "/var/cache/nginx/img" failed (2: No such file or directory)
RUN mkdir -p /var/cache/nginx

# Create a dummy, unsecure and temporary self-signed TLS certificate in order to
# prevent `no cert` error and let the server being up.
# Note: Mount a CA-signed certificate while running the container.
RUN mkdir /etc/nginx/ssl/ \
  && openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout /etc/nginx/ssl/privkey.pem \
    -out /etc/nginx/ssl/fullchain.pem \
    -subj '/CN=localhost'
RUN openssl dhparam -out /etc/nginx/ssl/ssl-dhparams.pem 128

# Check for syntax or potential errors
RUN nginx -t

EXPOSE 80
EXPOSE 443

# include -g daemon off; in the CMD in order for nginx to stay in the foreground,
# so that Docker can track the process properly (otherwise the container will stop immediately after starting)!
CMD ["nginx", "-g", "daemon off;"]