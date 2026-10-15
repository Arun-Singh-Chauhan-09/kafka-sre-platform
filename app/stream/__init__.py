"""Hotel price event pipeline: a producer and a consumer around one Kafka topic.

The services are deliberately small. They exist so the platform around them
(Kafka on Kubernetes, SLOs, alerts, runbooks, GitOps) has a realistic
workload to operate.
"""
