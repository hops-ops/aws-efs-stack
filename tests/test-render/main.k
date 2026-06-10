_composition = "apis/efsstoragestacks/composition.yaml"
_xrd = "apis/efsstoragestacks/definition.yaml"

_ready = [
    {type = "Ready", status = "True"}
    {type = "Synced", status = "True"}
]

_observed_file_system = {
    apiVersion = "efs.aws.m.upbound.io/v1beta1"
    kind = "FileSystem"
    metadata = {
        name = "gitkb"
        annotations = {"crossplane.io/composition-resource-name" = "file-system"}
    }
    status = {
        conditions = _ready
        atProvider = {
            id = "fs-0123456789abcdef0"
            arn = "arn:aws:elasticfilesystem:us-east-2:123456789012:file-system/fs-0123456789abcdef0"
            dnsName = "fs-0123456789abcdef0.efs.us-east-2.amazonaws.com"
            encrypted = True
        }
    }
}

_observed_security_group = {
    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
    kind = "SecurityGroup"
    metadata = {
        name = "gitkb-mt"
        annotations = {"crossplane.io/composition-resource-name" = "security-group"}
    }
    status = {
        conditions = _ready
        atProvider = {
            id = "sg-0efsmounttarget"
            arn = "arn:aws:ec2:us-east-2:123456789012:security-group/sg-0efsmounttarget"
        }
    }
}

_base_spec = {
    region = "us-east-2"
    cluster = {
        name = "platform"
    }
    network = {
        vpcId = "vpc-0123456789abcdef0"
        subnetIds = [
            "subnet-0123456789abcdef0"
            "subnet-0fedcba9876543210"
        ]
        clientSecurityGroupIds = [
            "sg-0123456789abcdef0"
        ]
    }
}

_items = [
    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "create-renders-filesystem-addon-and-pod-identity"
        spec = {
            compositionPath = _composition
            xrdPath = _xrd
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "EFSStorageStack"
                metadata.name = "gitkb"
                metadata.namespace = "default"
                spec = _base_spec
            }
            assertResources = [
                {
                    apiVersion = "efs.aws.m.upbound.io/v1beta1"
                    kind = "FileSystem"
                    metadata.name = "gitkb"
                    spec = {
                        managementPolicies = ["Create", "Observe", "Update", "LateInitialize"]
                        forProvider = {
                            region = "us-east-2"
                            encrypted = True
                            performanceMode = "generalPurpose"
                            throughputMode = "elastic"
                        }
                    }
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "SecurityGroup"
                    metadata.name = "gitkb-mt"
                    spec.forProvider = {
                        region = "us-east-2"
                        vpcId = "vpc-0123456789abcdef0"
                    }
                }
                {
                    apiVersion = "eks.aws.m.upbound.io/v1beta1"
                    kind = "Addon"
                    metadata.name = "gitkb-efs-csi"
                    spec.forProvider = {
                        region = "us-east-2"
                        clusterName = "platform"
                        addonName = "aws-efs-csi-driver"
                    }
                }
                {
                    apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                    kind = "PodIdentity"
                    metadata.name = "gitkb-efs-csi"
                    spec = {
                        region = "us-east-2"
                        clusterName = "platform"
                        serviceAccount = {
                            namespace = "kube-system"
                            name = "efs-csi-controller-sa"
                        }
                        managedPolicyArns = [
                            "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
                        ]
                    }
                }
            ]
        }
    }

    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "observed-filesystem-renders-network-and-storageclass"
        spec = {
            compositionPath = _composition
            xrdPath = _xrd
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "EFSStorageStack"
                metadata.name = "gitkb"
                metadata.namespace = "default"
                spec = _base_spec
            }
            observedResources = [
                _observed_file_system
                _observed_security_group
            ]
            assertResources = [
                {
                    apiVersion = "efs.aws.m.upbound.io/v1beta1"
                    kind = "BackupPolicy"
                    metadata.name = "gitkb"
                    spec.forProvider = {
                        region = "us-east-2"
                        fileSystemId = "fs-0123456789abcdef0"
                    }
                }
                {
                    apiVersion = "ec2.aws.m.upbound.io/v1beta1"
                    kind = "SecurityGroupIngressRule"
                    metadata.name = "gitkb-nfs-sg-0123456789abcdef0"
                    spec.forProvider = {
                        region = "us-east-2"
                        fromPort = 2049
                        toPort = 2049
                        securityGroupId = "sg-0efsmounttarget"
                        referencedSecurityGroupId = "sg-0123456789abcdef0"
                    }
                }
                {
                    apiVersion = "efs.aws.m.upbound.io/v1beta1"
                    kind = "MountTarget"
                    metadata.name = "gitkb-subnet-0123456789abcdef0"
                    spec.forProvider = {
                        region = "us-east-2"
                        fileSystemId = "fs-0123456789abcdef0"
                        subnetId = "subnet-0123456789abcdef0"
                        securityGroups = ["sg-0efsmounttarget"]
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "gitkb-efs-gitkb"
                    spec.forProvider.manifest = {
                        apiVersion = "storage.k8s.io/v1"
                        kind = "StorageClass"
                        metadata = {
                            name = "efs-gitkb"
                            annotations = {
                                "storageclass.kubernetes.io/is-default-class" = "false"
                            }
                        }
                        provisioner = "efs.csi.aws.com"
                        parameters = {
                            fileSystemId = "fs-0123456789abcdef0"
                            provisioningMode = "efs-ap"
                            basePath = "/gitkb"
                        }
                        reclaimPolicy = "Retain"
                    }
                }
            ]
        }
    }

    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "import-existing-filesystem-is-observe-only"
        spec = {
            compositionPath = _composition
            xrdPath = _xrd
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "EFSStorageStack"
                metadata.name = "gitkb-import"
                metadata.namespace = "default"
                spec = _base_spec | {
                    fileSystem = {
                        create = False
                        externalName = "fs-0imported"
                    }
                    security = {
                        manageSecurityGroup = False
                        securityGroupId = "sg-0existingefs"
                    }
                    csi = {
                        mode = "existing"
                        podIdentity.enabled = False
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "efs.aws.m.upbound.io/v1beta1"
                    kind = "FileSystem"
                    metadata = {
                        name = "gitkb-import"
                        annotations = {
                            "crossplane.io/external-name" = "fs-0imported"
                        }
                    }
                    spec.managementPolicies = ["Observe", "LateInitialize"]
                }
                {
                    apiVersion = "efs.aws.m.upbound.io/v1beta1"
                    kind = "MountTarget"
                    metadata.name = "gitkb-import-subnet-0123456789abcdef0"
                    spec.forProvider = {
                        fileSystemId = "fs-0imported"
                        securityGroups = ["sg-0existingefs"]
                    }
                }
            ]
        }
    }

    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "existing-addon-mode-skips-managed-addon"
        spec = {
            compositionPath = _composition
            xrdPath = _xrd
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "EFSStorageStack"
                metadata.name = "gitkb-existing-csi"
                metadata.namespace = "default"
                spec = _base_spec | {
                    cluster = {
                        name = "platform"
                        addon.installEfsCsiDriver = False
                        podIdentity.enabled = False
                    }
                    csi = {
                        mode = "existing"
                        podIdentity.enabled = False
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "efs.aws.m.upbound.io/v1beta1"
                    kind = "FileSystem"
                    metadata.name = "gitkb-existing-csi"
                }
            ]
        }
    }

    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "storageclasses-can-be-disabled"
        spec = {
            compositionPath = _composition
            xrdPath = _xrd
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "EFSStorageStack"
                metadata.name = "gitkb-no-storageclass"
                metadata.namespace = "default"
                spec = _base_spec | {
                    storageClasses = []
                }
            }
            observedResources = [
                _observed_file_system
                _observed_security_group
            ]
            assertResources = [
                {
                    apiVersion = "efs.aws.m.upbound.io/v1beta1"
                    kind = "MountTarget"
                    metadata.name = "gitkb-no-storageclass-subnet-0123456789abcdef0"
                }
            ]
        }
    }

    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "delete-protected-defaults"
        spec = {
            compositionPath = _composition
            xrdPath = _xrd
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "EFSStorageStack"
                metadata.name = "gitkb"
                metadata.namespace = "default"
                spec = _base_spec
            }
            observedResources = [
                _observed_file_system
                _observed_security_group
            ]
            assertResources = [
                {
                    apiVersion = "efs.aws.m.upbound.io/v1beta1"
                    kind = "FileSystem"
                    metadata.name = "gitkb"
                    spec.managementPolicies = ["Create", "Observe", "Update", "LateInitialize"]
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "gitkb-efs-gitkb"
                    spec.forProvider.manifest.reclaimPolicy = "Retain"
                }
            ]
        }
    }
]

items = _items
