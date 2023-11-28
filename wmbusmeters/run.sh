#!/usr/bin/with-contenv bashio

CONFIG_PATH=/data/options.json
LOOK_FOR_METER=$(bashio::config 'look_for_meters')
CONFIG_DATA_PATH=$(bashio::jq "${CONFIG_PATH}" '.data_path')
CONFIG_CONF=$(bashio::jq "${CONFIG_PATH}" '.config')
CONFIG_METERS=$(bashio::jq "${CONFIG_PATH}" '.meters')
CONFIG_MQTT=$(bashio::jq "${CONFIG_PATH}" '.mqtt')

/wmbusmeters/wmbusmeters --version

rm -rf $CONFIG_DATA_PATH/etc/*

bashio::log.info "Syncing wmbusmeters configuration ..."
if ! bashio::fs.directory_exists "${CONFIG_DATA_PATH}/logs/meter_readings"; then
    mkdir -p "${CONFIG_DATA_PATH}/logs/meter_readings"
fi
if ! bashio::fs.directory_exists "${CONFIG_DATA_PATH}/etc/wmbusmeters.d"; then
    mkdir -p "${CONFIG_DATA_PATH}/etc/wmbusmeters.d"
fi

echo -e "$CONFIG_CONF" | jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]' > $CONFIG_DATA_PATH/etc/wmbusmeters.conf

# read each line of config file
while read -r line; do
    # split the line into parameter and values
    param="${line%=*}"
    values="${line#*=}"
    # check if values contain the delimiter ";"
    if [[ "$values" == *";"* ]]; then
        # split values into an array using ";" as the delimiter
        IFS=";" read -ra arr <<< "$values"
        # extract the first key from the parameter
        first_key="${param%=*}"
        # loop through the array and create separate key-value pairs
        for value in "${arr[@]}"; do
            echo "$first_key=$value"
        done
    else
        # if values do not contain ";", print the original key-value pair
        echo "$line"
    fi
done < $CONFIG_DATA_PATH/etc/wmbusmeters.conf > $CONFIG_DATA_PATH/etc/wmbusmeters.conf_tmp
mv $CONFIG_DATA_PATH/etc/wmbusmeters.conf_tmp $CONFIG_DATA_PATH/etc/wmbusmeters.conf

bashio::log.info "Registering meters ..."
rm -f $CONFIG_DATA_PATH/etc/wmbusmeters.d/*
meter_no=0
IFS=$'\n'

if [ "${LOOK_FOR_METER}" = "no" ]
then
    for meter in $(jq -c -M '.meters[]' $CONFIG_PATH)
    do
        meter_no=$(( meter_no+1 ))
        METER_NAME=$(printf 'meter-%04d' "$(( meter_no ))")
        bashio::log.info "Adding $METER_NAME ..."
        METER_DATA=$(printf '%s\n' $meter | jq --raw-output -c -M '.') 
        echo -e "$METER_DATA" | jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]' > $CONFIG_DATA_PATH/etc/wmbusmeters.d/$METER_NAME
    done
fi

bashio::log.info "Generating MQTT configuration ... "
if bashio::jq.exists "${CONFIG_PATH}" ".mqtt.server"
then
    MQTT_HOST=$(bashio::jq "${CONFIG_PATH}" ".mqtt.server")
    if bashio::jq.exists "${CONFIG_PATH}" ".mqtt.port"; then MQTT_PORT=$(bashio::jq "${CONFIG_PATH}" ".mqtt.port"); fi
    if bashio::jq.exists "${CONFIG_PATH}" ".mqtt.username"; then MQTT_USER=$(bashio::jq "${CONFIG_PATH}" ".mqtt.username"); fi
    if bashio::jq.exists "${CONFIG_PATH}" ".mqtt.password"; then MQTT_PASSWORD=$(bashio::jq "${CONFIG_PATH}" ".mqtt.password"); fi
else
    MQTT_HOST=$(bashio::services mqtt "host")
    MQTT_PORT=$(bashio::services mqtt "port")
    MQTT_USER=$(bashio::services mqtt "username")
    MQTT_PASSWORD=$(bashio::services mqtt "password")
fi

bashio::log.info "Broker $MQTT_HOST will be used."
pub_args=('-h' $MQTT_HOST )
pub_args_quoted=('-h' \'$MQTT_HOST\' )
[[ ! -z ${MQTT_PORT+x} ]] && pub_args+=( '-p' $MQTT_PORT ) && pub_args_quoted+=( '-p' \'$MQTT_PORT\' )
[[ ! -z ${MQTT_USER+x} ]] && pub_args+=( '-u' $MQTT_USER ) && pub_args_quoted+=( '-u' \'$MQTT_USER\' )
[[ ! -z ${MQTT_PASSWORD+x} ]] && pub_args+=( '-P' $MQTT_PASSWORD ) && pub_args_quoted+=( '-P' \'$MQTT_PASSWORD\' )

cat > /wmbusmeters/mosquitto_pub.sh << EOL
#!/usr/bin/with-contenv bashio
TOPIC=\$1
MESSAGE=\$2
/usr/bin/mosquitto_pub ${pub_args_quoted[@]} -r -t "\$TOPIC" -m "\$MESSAGE"
EOL
chmod a+x /wmbusmeters/mosquitto_pub.sh

CONFIG_MQTTDISCOVERY_ENABLED=$(bashio::config "enable_mqtt_discovery")
if [ $CONFIG_MQTTDISCOVERY_ENABLED == "true" ]; then
    cp -r /mqtt_discovery $CONFIG_DATA_PATH/etc
    bashio::log.info "MQTT discovery"
    /mqtt_discovery.sh ${pub_args[@]} -c $CONFIG_PATH -w $CONFIG_DATA_PATH || true
fi

bashio::log.info "Starting web configuration service."
python3 /rootfs/flask/app.py &

bashio::log.info "Running wmbusmeters ..."
/wmbusmeters/wmbusmeters --useconfig=$CONFIG_DATA_PATH
