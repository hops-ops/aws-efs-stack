# aws-efs-stack

`EFSStorageStack` (`efsstoragestacks.aws.hops.ops.com.ai`) provisions Amazon
EFS shared storage for EKS workloads, installs the EFS CSI managed add-on by
default, and creates Kubernetes `StorageClass` resources for RWX PVCs.

## Why EFSStorageStack?

GitKB and similar workloads need shared `ReadWriteMany` storage that survives
pod replacement and can be mounted from more than one node. EKS Auto Mode ships
the EBS CSI driver, but EBS volumes are not RWX. This stack keeps EFS separate
from cluster creation so storage can be added, imported, or replaced without
changing `AutoEKSCluster`.

With this stack:

- An encrypted EFS file system is created by default.
- Data-bearing file systems omit `Delete` from `managementPolicies` by default.
- Existing file systems can be imported with observe-only policies.
- Mount targets are created for each configured subnet.
- A mount target security group allows NFS TCP 2049 from client security groups.
- The `aws-efs-csi-driver` EKS managed add-on is installed unless disabled.
- Pod Identity grants the CSI controller the AWS managed EFS CSI policy.
- Kubernetes `StorageClass` objects default to `reclaimPolicy: Retain`.

## Getting Started

Create EFS storage for a platform cluster:

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: EFSStorageStack
metadata:
  name: gitkb
  namespace: default
spec:
  region: us-east-2
  cluster:
    name: platform
  network:
    vpcId: vpc-0123456789abcdef0
    subnetIds:
      - subnet-0123456789abcdef0
      - subnet-0fedcba9876543210
    clientSecurityGroupIds:
      - sg-0123456789abcdef0
```

The default `StorageClass` is named `efs-gitkb` and uses dynamic EFS access
points:

```text
provisioner: efs.csi.aws.com
reclaimPolicy: Retain
parameters.fileSystemId: <observed EFS file system ID>
parameters.provisioningMode: efs-ap
```

## Data Safety

The file system is data-bearing. By default the stack renders:

```yaml
spec:
  fileSystem:
    managementPolicies:
      - Create
      - Observe
      - Update
      - LateInitialize
```

`Delete` is intentionally omitted. Imported file systems default to
`["Observe", "LateInitialize"]`. StorageClasses default to
`reclaimPolicy: Retain` so PVC deletion does not delete the backing EFS access
point data unexpectedly.

## Import Existing EFS

Use `create: false` with an EFS file system ID. If you also want to use an
existing mount-target security group, set `manageSecurityGroup: false`.

```yaml
spec:
  fileSystem:
    create: false
    externalName: fs-0123456789abcdef0
  security:
    manageSecurityGroup: false
    securityGroupId: sg-0fedcba9876543210
```

## Existing CSI Driver

Disable managed add-on and Pod Identity rendering when the cluster already
installs and authorizes the EFS CSI driver:

```yaml
spec:
  cluster:
    addon:
      installEfsCsiDriver: false
    podIdentity:
      enabled: false
  csi:
    mode: existing
    podIdentity:
      enabled: false
```

## StorageClasses

Omit `storageClasses` to get one non-default class named `efs-gitkb`. Set an
empty list to disable StorageClass rendering:

```yaml
spec:
  storageClasses: []
```

## Live Smoke

The e2e test in `tests/e2etest-efsstoragestack` expects a real EKS cluster,
provider credentials, and target kubeconfig. It creates a PVC, a writer Job, and
a reader Job that mounts the same claim and verifies the written probe file.

Prepare local inputs:

```text
tests/e2etest-efsstoragestack/secrets/aws-creds
tests/e2etest-efsstoragestack/secrets/target-kubeconfig
tests/e2etest-efsstoragestack/env/AWS_REGION
tests/e2etest-efsstoragestack/env/EKS_CLUSTER_NAME
tests/e2etest-efsstoragestack/env/VPC_ID
tests/e2etest-efsstoragestack/env/PRIVATE_SUBNET_ID_A
tests/e2etest-efsstoragestack/env/PRIVATE_SUBNET_ID_B
tests/e2etest-efsstoragestack/env/EKS_CLIENT_SECURITY_GROUP_ID
```

Run:

```sh
make e2e
```

## Development

```sh
make render
make validate
make test
```
