FROM registry.fedoraproject.org/fedora@sha256:cd3513b19e87220eb6fba1aeb041cf88f9c00c3b1de213c36db7532c383f4a1c

RUN dnf -y install bash curl && \
    dnf clean all && \
    rm -rf /var/cache/dnf

COPY --chmod=0755 setup-qwen-local.sh /usr/local/bin/setup-qwen-local

ENTRYPOINT ["/usr/local/bin/setup-qwen-local"]
