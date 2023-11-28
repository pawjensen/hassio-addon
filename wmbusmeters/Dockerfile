ARG BUILD_FROM
FROM wmbusmeters/wmbusmeters-ha-addon-edge-aarch64:1.13.1 as BUILD

ADD mqtt_discovery/ /mqtt_discovery/
COPY mqtt_discovery.sh /
RUN chmod a+x /mqtt_discovery.sh

COPY run.sh /
RUN chmod a+x /run.sh

COPY rootfs /rootfs
RUN chmod a+x /etc/services.d/nginx/run
RUN chmod a+x /etc/services.d/nginx/finish
RUN chmod a+x /etc/cont-init.d/nginx.sh

WORKDIR /

CMD ["/run.sh"]