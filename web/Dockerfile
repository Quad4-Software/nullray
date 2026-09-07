# nullray.xyz static site: busybox httpd, ~1.4MB image, rootless.
#
# Build context is the repo root so install.sh ships at /install:
#   docker build -f web/Dockerfile -t nullray-web .
#   docker run --rm -p 8080:8080 nullray-web
#
# Busybox httpd serves / -> index.html and /install -> the installer script
# (extensionless file, octet-stream, safe for curl | sh).

# hadolint ignore=DL3006
FROM busybox:1.37-musl@sha256:fc6dddc4c44b1bfe37f41cae8e67d1693828e8f42a91862816d7953e2c9d3f23

RUN install -d -m 755 /www
COPY --chmod=644 web/index.html /www/index.html
COPY --chmod=644 install.sh /www/install

USER 1000
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=2s \
	CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1

CMD ["httpd", "-f", "-p", "8080", "-h", "/www"]
