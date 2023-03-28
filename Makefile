.PHONY: build

build:
	@docker build -t gbieul/spark-base-hadoop:3.3.2 ./docker/spark-base
	@docker build -t gbieul/spark-master-hadoop:3.3.2 ./docker/spark-master
	@docker build -t gbieul/spark-worker-hadoop:3.3.2 ./docker/spark-worker