#!/bin/bash

# Este trecho rodará independente de termos um container master ou
# worker. Necesário para funcionamento do HDFS e para comunicação
# dos containers/nodes.
/etc/init.d/ssh start

# Abaixo temos o trecho que rodará apenas no master.
if [[ $HOSTNAME = spark-master ]]; then
    
    # Formatamos o namenode
    hdfs namenode -format

    # Iniciamos os serviços
    $HADOOP_HOME/sbin/start-dfs.sh
    $HADOOP_HOME/sbin/start-yarn.sh

    # Inicio do mysql - metastore o Hive
    service mysql start

    # Criação de diretórios no ambiente distribuído do HDFS
    hdfs dfs -mkdir -p /user/$HDFS_NAMENODE_USER/datasets
    hdfs dfs -mkdir -p /user/$HDFS_NAMENODE_USER/datasets_processed

    # Roteiro 4
    hdfs dfs -mkdir -p /user/$HDFS_NAMENODE_USER/spark-logs
    start-history-server.sh

    # Configs de Zookeeper
    touch /var/lib/zookeeper/myid
    echo "1" >> /var/lib/zookeeper/myid
    $ZOOKEEPER_HOME/bin/zkServer.sh start

    # Configs de Kafka
    # Adiciona quebra de linha ao fim do arquivo
    sed -i 's/$/\n/' $KAFKA_HOME/config/server.properties

    # Adiciona o id do Broker. O Master será o número 0.
    echo "broker.id=0" >> $KAFKA_HOME/config/server.properties

    # Configs de Hive, configurando o metastore, definindo senha, etc...
    mysql -u $GLOBAL_USER -Bse \
    "CREATE DATABASE metastore; \
    USE metastore; \
    SOURCE $HIVE_HOME/scripts/metastore/upgrade/mysql/hive-schema-3.1.0.mysql.sql; \
    CREATE USER 'hive'@'localhost' IDENTIFIED BY 'password'; \
    REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'hive'@'localhost'; \
    GRANT ALL PRIVILEGES ON metastore.* TO 'hive'@'localhost' IDENTIFIED BY 'password'; \
    FLUSH PRIVILEGES; quit;"

    # Caso mantenha notebooks personalizados na pasta que tem bind mount com o 
    # container /user_data, o trecho abaixo automaticamente fará o processo de 
    # confiar em todos os notebooks, também liberando o server do jupyter de
    # solicitar um token
    cd /user_data
    jupyter trust *.ipynb
    jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token='' --NotebookApp.password='' &

    # Iniciando o Kafka
    cd /
    $KAFKA_HOME/bin/kafka-server-start.sh $KAFKA_HOME/config/server.properties &

    # Inicio dos serviços do Hive. Nao recomendado: Redirecionamos
    # os outputs para uma localização inexistente para que as linhas
    # não bloqueiem o shell
    nohup hive --service metastore > /dev/null 2>&1 &
    nohup hive --service hiveserver2 > /dev/null 2>&1 &

# E abaixo temos o trecho que rodará nos workers
else
    # Configs de Zookeper para workers
    touch /var/lib/zookeeper/myid
    echo "$((${HOSTNAME: -1}+1))" >> /var/lib/zookeeper/myid

    # Configs de Kafka. Vamos numerando os brokers.
    sed -i 's/$/\n/' $KAFKA_HOME/config/server.properties
    echo "broker.id=$((${HOSTNAME: -1}+1))" >> $KAFKA_HOME/config/server.properties

    # Configs de HDFS nos dataNodes (workers)
    $HADOOP_HOME/sbin/hadoop-daemon.sh start datanode &
    $HADOOP_HOME/bin/yarn nodemanager &
    
    # Inicio do serviço do Zookeeper
    $ZOOKEEPER_HOME/bin/zkServer.sh start &

    # Início do Kafka
    $KAFKA_HOME/bin/kafka-server-start.sh $KAFKA_HOME/config/server.properties

fi

while :; do sleep 2073600; done
