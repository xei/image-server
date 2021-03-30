# Nginx Image Server
This is an efficient, secure and containerized `image filtering server` that uses [Nginx](https://nginx.org/) as a web server or reverse proxy to cache and serve images and filter them (scale down, crop, add watermark, compress, encode, etc) `on-the-fly` using a patched and unofficial version of [http_image_filter_module](http://nginx.org/en/docs/http/ngx_http_image_filter_module.html) that support adding watermark.

By using this server, you don't need to store multiple versions of your images with different sizes and formats. You just store ONE VERSION (the original images) and filter them on-the-fly. Nginx will cache the filtered images for future requests.

Filtering images is a resource-intensive task so it's highly recommended to uncomment [ngx_http_secure_link_module](http://nginx.org/en/docs/http/ngx_http_secure_link_module.html) section in `front-server.conf` file. You can find more info about ` Nginx secure link module` at [this blog post](https://www.nginx.com/blog/securing-urls-secure-link-module-nginx-plus/).

## Build the Docker image
```
$ docker build \
    --build-arg HOST_NAME=img.example.com \
    --build-arg SECRET_KEY=MY_SECRET_KEY \
    -t image-server:latest \
    .
```

It's flexible to specify the `Nginx` version (or the version of the other dependencies such as `OpenSSL`) and you can pass the versions using `--build-arg` switch.
```
$ docker build \
    --build-arg NGINX_VERSION=1.18.0 \
    --build-arg HOST_NAME=img.example.com \
    --build-arg SECRET_KEY=MY_SECRET_KEY \
    -t image-server:latest \
    .
```

## Run the Docker container
Run the Docker container using the following command:
```
$ docker run -d \
    --name image-server-container
    -p 80:80 \
    -p 443:443 \
    -v ~/nginx/conf/front-server.conf:/etc/nginx/conf.d/front-server.conf:ro \
    -v ~/ssl/cert/live/img.example.com/fullchain.pem:/etc/nginx/ssl/fullchain.pem \
    -v ~/ssl/cert/live/img.example.com/privkey.pem:/etc/nginx/ssl/privkey.pem \
    -v ~/ssl/cert/ssl-dhparams.pem:/etc/nginx/ssl/ssl-dhparams.pem \
    -v ~/webroot:/usr/share/nginx/acme-challenge \
    -v ~/nginx/log:/var/log/nginx \
    -v ~/img/watermark.png:/usr/share/nginx/img/watermark.png \
    -v ~/img/raw:/usr/share/nginx/img/raw \
    -- restart unless-stopped \
    image-server
```

You can test the server with some default configurations:
```
$ docker run -d \
    --name image-server-container
    -p 80:80 \
    -p 443:443 \
    -v ~/webroot:/usr/share/nginx/acme-challenge \
    -v ~/nginx/log:/var/log/nginx \
    -- restart unless-stopped \
    file-server-image
```
The above command will run the server using an unsecure sel-signed TLS certificate. It's just for testing purpose and should not be used in production. Get a free `Let's Encrypt` certificate ASAP and mount it while running the container.

## Request for the initial TLS certificate:
If you have not launched the image server yet, you can get a TLS certificate using a `standalone Certbot server` (first, remove `--staging --dry-run` when you are sure about the configurations):
```
$ docker run --rm \
    -p 80:80 \
    -v ~/ssl/cert:/etc/letsencrypt \
    -v ~/ssl/log:/var/log/letsencrypt \
    certbot/certbot \
    certonly --standalone -d img.example.com --email img@example.com  --agree-tos --no-eff-email --staging --dry-run
``` 
But if the file server is up with the self-signed certificate, use the following command instead to get a TLS certificate using `Certbot webroot plugin`:
```
$ docker run --rm \
    -v ~/ssl/cert:/etc/letsencrypt \
    -v ~/ssl/log:/var/log/letsencrypt \
    -v ~/webroot:/var/www/acme-challenge \
    certbot/certbot \
    certonly --webroot --webroot-path /var/www/acme-challenge -d img.example.com --email img@example.com  --agree-tos --no-eff-email --staging --dry-run
```

## Modify file server on-the-fly
```
$ docker ps
$ docker exec -it CONTAINER_ID bash
root@CONTAINER_ID:/etc/nginx# vim /etc/nginx/conf.d/image-filter-server.conf
$ nginx -s reload

Or:
$ docker exec -it file-server-container nginx -s reload

Or:
$ docker kill -s SIGHUP file-server-container
```
`SIGHUP` signal will reload the Nginx.

# Using Docker-compose in order to automate the renewal process
At first (image server is down), get a TLS certificate using a standalone server:
```
$ docker run --rm \
    -p 80:80 \
    -v ~/ssl/cert:/etc/letsencrypt \
    -v ~/ssl/log:/var/log/letsencrypt \
    certbot/certbot \
    certonly --standalone -d img.example.com --email img@example.com  --agree-tos --no-eff-email --staging --dry-run
```
Then run `docker-compose up -d` to bring up the image server and a container responsible for checking the certificate and request for a new one.

This will check if your certificate is up for renewal every 12 hours as recommended by `Let’s Encrypt` and makes `Nginx` reload its configuration (and certificates) every six hours in the background and launches nginx in the foreground. (https://pentacent.medium.com/nginx-and-lets-encrypt-with-docker-in-less-than-5-minutes-b4b8a60d3a71)

## Helper Docker-compose commands:

```
$ docker-compose up -d
$ docker-compose ps
$ docker-compose logs fileserver
$ docker logs -f file-server-container
$ docker-compose exec file-server-containe ls -la /etc/nginx/ssl
$ docker-compose stop file-server-container
$ docker cp file-server-container:/etc/nginx/conf.d/front-server.conf /host/path/nginx.conf
$ docker-compose kill -s SIGHUP file-server-container -> reload nginx
```

## Available options for adding a WATERMARK
```
image_filter watermark;

image_filter_watermark_width_from 300;
image_filter_watermark_height_from 400;
    
image_filter_watermark "PATH_TO_FILE";
image_filter_watermark_position center-center; # top-left|top-right|bottom-right|bottom-left|right-center|left-center|bottom-center|top-center|center-center|center-random`
```

`image_filter_watermark_width_from` - Minimal width image (after resize and crop) of when to use watermark.
`image_filter_watermark_height_from` - Minimal height image (after resize and crop) of when to use watermark.

If width or height image (after resize and crop) more then `image_filter_watermark_height_from` or `image_filter_watermark_width_from` then image gets watermark.

`image_filter_watermark` - path to watermark file.
`image_filter_watermark_position` - position of watermark, available values are `top-left|top-right|bottom-right|bottom-left|right-center|left-center|bottom-center|top-center|center-center|center-random`.


### Example Usage

Base Usage:

```
    location /img/ {
        image_filter watermark;

        image_filter_watermark "PATH_TO_FILE";
        image_filter_watermark_position center-center;
    }
```

Usage with resize and crop:

```
   location ~ ^/r/(\d+|-)x(\d+|-)/c/(\d+|-)x(\d+|-)/(.+) {
       set                         $resize_width  $1;
       set                         $resize_height $2;
       set                         $crop_width  $3;
       set                         $crop_height $4;

       alias                       /PATH_TO_STATIC/web/$5;
       try_files                   "" @404;

       image_filter                resize $resize_width $resize_height;
       image_filter                crop   $crop_width $crop_height;

       image_filter_jpeg_quality   95;
       image_filter_buffer         2M;

       image_filter_watermark_width_from 400;   # Minimal width (after resize) of when to use watermark
       image_filter_watermark_height_from 400;  # Minimal height (after resize) of when to use watermark

       image_filter_watermark "PATH_TO_FILE";
       image_filter_watermark_position center-center;
   }
```

### Example test memory leaks

```
ab -n 3000 -c 10 -k  http://image-resize.local/r/500x-/some-file.jpg
```

While there is a load test,  track at how the RAM behaves
