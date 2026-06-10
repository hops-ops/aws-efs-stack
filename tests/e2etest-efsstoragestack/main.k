# e2etest-efsstoragestack - AWS EFS StorageClass live smoke
#
# Prerequisites:
# 1. secrets/aws-creds: AWS shared config credentials for the test account.
# 2. secrets/target-kubeconfig: kubeconfig for the target EKS cluster.
# 3. env/AWS_REGION, env/EKS_CLUSTER_NAME, env/VPC_ID,
#    env/PRIVATE_SUBNET_ID_A, env/PRIVATE_SUBNET_ID_B,
#    env/EKS_CLIENT_SECURITY_GROUP_ID.
#
# The test creates one EFSStorageStack plus Kubernetes Objects in the target
# cluster: a namespace, RWX PVC, writer Job, and reader Job. The reader waits for
# the writer's file, exercising dynamic EFS access point provisioning across pods.

import base64
import datetime
import file
import math

_now = str(int(math.floor(datetime.ticks())))
_name = "e2e-efs-" + _now
_namespace = "default"
_target_namespace = _name
_region = file.read("env/AWS_REGION").strip()
_cluster_name = file.read("env/EKS_CLUSTER_NAME").strip()
_vpc_id = file.read("env/VPC_ID").strip()
_subnet_ids = [
    file.read("env/PRIVATE_SUBNET_ID_A").strip()
    file.read("env/PRIVATE_SUBNET_ID_B").strip()
]
_client_security_group_ids = [
    file.read("env/EKS_CLIENT_SECURITY_GROUP_ID").strip()
]
_aws_creds = base64.encode(file.read("secrets/aws-creds"))
_target_kubeconfig = base64.encode(file.read("secrets/target-kubeconfig"))
_probe = "efs-smoke-" + _now

_items = [
    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "E2ETest"
        metadata.name = "efsstoragestack"
        spec = {
            crossplane = {
                autoUpgrade.channel = "Rapid"
            }
            defaultConditions = ["Ready"]
            timeoutSeconds = 3600
            cleanupTimeoutSeconds = 1800
            skipDelete = False
            extraResources = [
                {
                    apiVersion = "v1"
                    kind = "Secret"
                    metadata = {
                        name = "aws-creds"
                        namespace = _namespace
                    }
                    data = {
                        creds = _aws_creds
                    }
                }
                {
                    apiVersion = "aws.m.upbound.io/v1beta1"
                    kind = "ProviderConfig"
                    metadata = {
                        name = "default"
                        namespace = _namespace
                    }
                    spec = {
                        credentials = {
                            source = "Secret"
                            secretRef = {
                                namespace = _namespace
                                name = "aws-creds"
                                key = "creds"
                            }
                        }
                    }
                }
                {
                    apiVersion = "v1"
                    kind = "Secret"
                    metadata = {
                        name = "target-kubeconfig"
                        namespace = _namespace
                    }
                    data = {
                        kubeconfig = _target_kubeconfig
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "ProviderConfig"
                    metadata = {
                        name = _cluster_name
                        namespace = _namespace
                    }
                    spec = {
                        credentials = {
                            source = "Secret"
                            secretRef = {
                                namespace = _namespace
                                name = "target-kubeconfig"
                                key = "kubeconfig"
                            }
                        }
                    }
                }
            ]
            manifests = [
                {
                    apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                    kind = "EFSStorageStack"
                    metadata = {
                        name = _name
                        namespace = _namespace
                    }
                    spec = {
                        region = _region
                        providerConfigRefs = {
                            kubernetes = {
                                name = _cluster_name
                                kind = "ProviderConfig"
                            }
                        }
                        cluster = {
                            name = _cluster_name
                        }
                        network = {
                            vpcId = _vpc_id
                            subnetIds = _subnet_ids
                            clientSecurityGroupIds = _client_security_group_ids
                        }
                        tags = {
                            "e2etest" = "true"
                            "test-run" = _now
                            "repo" = "https://github.com/hops-ops/aws-efs-stack"
                        }
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata = {
                        name = _name + "-namespace"
                        namespace = _namespace
                    }
                    spec = {
                        forProvider.manifest = {
                            apiVersion = "v1"
                            kind = "Namespace"
                            metadata.name = _target_namespace
                        }
                        providerConfigRef = {
                            name = _cluster_name
                            kind = "ProviderConfig"
                        }
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata = {
                        name = _name + "-pvc"
                        namespace = _namespace
                    }
                    spec = {
                        forProvider.manifest = {
                            apiVersion = "v1"
                            kind = "PersistentVolumeClaim"
                            metadata = {
                                name = "efs-smoke"
                                namespace = _target_namespace
                            }
                            spec = {
                                accessModes = ["ReadWriteMany"]
                                storageClassName = "efs-gitkb"
                                resources.requests.storage = "1Gi"
                            }
                        }
                        readiness = {
                            policy = "DeriveFromCelQuery"
                            celQuery = "has(object.status.phase) && object.status.phase == 'Bound'"
                        }
                        references = [
                            {
                                dependsOn = {
                                    name = _name + "-namespace"
                                    namespace = _namespace
                                }
                            }
                        ]
                        providerConfigRef = {
                            name = _cluster_name
                            kind = "ProviderConfig"
                        }
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata = {
                        name = _name + "-writer"
                        namespace = _namespace
                    }
                    spec = {
                        forProvider.manifest = {
                            apiVersion = "batch/v1"
                            kind = "Job"
                            metadata = {
                                name = "efs-smoke-writer"
                                namespace = _target_namespace
                            }
                            spec = {
                                backoffLimit = 6
                                template.spec = {
                                    restartPolicy = "OnFailure"
                                    containers = [
                                        {
                                            name = "writer"
                                            image = "busybox:1.37.0"
                                            command = ["sh", "-c", "echo " + _probe + " > /data/probe.txt && sync"]
                                            volumeMounts = [
                                                {
                                                    name = "data"
                                                    mountPath = "/data"
                                                }
                                            ]
                                        }
                                    ]
                                    volumes = [
                                        {
                                            name = "data"
                                            persistentVolumeClaim.claimName = "efs-smoke"
                                        }
                                    ]
                                }
                            }
                        }
                        readiness = {
                            policy = "DeriveFromCelQuery"
                            celQuery = "has(object.status.succeeded) && object.status.succeeded >= 1"
                        }
                        references = [
                            {
                                dependsOn = {
                                    name = _name + "-pvc"
                                    namespace = _namespace
                                }
                            }
                        ]
                        providerConfigRef = {
                            name = _cluster_name
                            kind = "ProviderConfig"
                        }
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata = {
                        name = _name + "-reader"
                        namespace = _namespace
                    }
                    spec = {
                        forProvider.manifest = {
                            apiVersion = "batch/v1"
                            kind = "Job"
                            metadata = {
                                name = "efs-smoke-reader"
                                namespace = _target_namespace
                            }
                            spec = {
                                backoffLimit = 6
                                template.spec = {
                                    restartPolicy = "OnFailure"
                                    containers = [
                                        {
                                            name = "reader"
                                            image = "busybox:1.37.0"
                                            command = [
                                                "sh"
                                                "-c"
                                                "for i in $(seq 1 120); do test -f /data/probe.txt && grep -qx " + _probe + " /data/probe.txt && exit 0; sleep 5; done; cat /data/probe.txt 2>/dev/null || true; exit 1"
                                            ]
                                            volumeMounts = [
                                                {
                                                    name = "data"
                                                    mountPath = "/data"
                                                }
                                            ]
                                        }
                                    ]
                                    volumes = [
                                        {
                                            name = "data"
                                            persistentVolumeClaim.claimName = "efs-smoke"
                                        }
                                    ]
                                }
                            }
                        }
                        readiness = {
                            policy = "DeriveFromCelQuery"
                            celQuery = "has(object.status.succeeded) && object.status.succeeded >= 1"
                        }
                        references = [
                            {
                                dependsOn = {
                                    name = _name + "-writer"
                                    namespace = _namespace
                                }
                            }
                        ]
                        providerConfigRef = {
                            name = _cluster_name
                            kind = "ProviderConfig"
                        }
                    }
                }
            ]
        }
    }
]

items = _items
