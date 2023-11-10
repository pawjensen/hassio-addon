# FROM wmbusmeters/wmbusmeters-ha-addon-edge-aarch64
# FROM wmbusmeters/wmbusmeters-ha-addon-aarch64
# FROM wmbusmeters/wmbusmeters-ha-addon-aarch64:1.13.0
FROM bibolv/wmbusmeters-ha-addon-edge-armv7

COPY run.sh /
RUN chmod a+x /run.sh

COPY run1.sh /
RUN chmod a+x /run1.sh

# COPY rootfs/flask/app.py /flask/app.py 

WORKDIR /

CMD ["/run.sh"]
