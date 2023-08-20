FROM alpine:3.18 as bind

RUN apk --update --no-cache add \
    bind=9.18.16-r0 

FROM alpine:3.18 as octodns

ARG ENVIRONMENT=internal

RUN apk --update --no-cache add \
    python3=3.11.4-r0 \
    py3-pip=23.1.2-r0 \
    py3-virtualenv=20.23.1-r0 \
    git=2.40.1-r0 && \
    mkdir -p /octodns

COPY . /octodns
WORKDIR /octodns
RUN sh ./script/bootstrap && \
    . env/bin/activate && \
    SOA_SERIAL="$(date +%s)" octodns-sync --config-file=./config/${ENVIRONMENT}/bootstrap.yaml --doit

FROM scratch as build

ARG ENVIRONMENT=internal
ARG AXFR_KEY_NAME=octodns
ARG AXFR_KEY_SECRET

COPY --from=bind / /
COPY --chown=root:named ./config/${ENVIRONMENT}/bind/ /etc/bind

RUN if [[ -z "${AXFR_KEY_SECRET}" ]]; then /usr/sbin/tsig-keygen -a hmac-sha256 ${AXFR_KEY_NAME} > /etc/bind/${AXFR_KEY_NAME}.key; fi
RUN if [[ -n "${AXFR_KEY_SECRET}" ]]; then echo -e "key \"${AXFR_KEY_NAME}\" { \n\talgorithm hmac-sha256;\n\tsecret \"${AXFR_KEY_SECRET}\";\n};" > /etc/bind/${AXFR_KEY_NAME}.key; fi 
RUN cat /etc/bind/${AXFR_KEY_NAME}.key

RUN sed -i "s/%%AXFR_KEY_NAME%%/${AXFR_KEY_NAME}/g;" /etc/bind/named.conf
RUN cat /etc/bind/named.conf

COPY --from=octodns --chown=named:named /octodns/zones/*.zone /var/bind/pri

RUN mkdir -p /var/run/named && chown root:named /var/run/named && chmod 770 /var/run/named

USER named

RUN /usr/bin/named-checkconf -z -j /etc/bind/named.conf


FROM scratch

COPY --from=build / /

VOLUME [ "/var/bind", "/etc/bind" ]

EXPOSE 53/tcp 53/udp 953/tcp

ENTRYPOINT [ "/usr/sbin/named" ]
CMD [ "-g", "-f", "-c", "/etc/bind/named.conf", "-u", "named" ]