"""Architecture diagram for gcp-workload-identity-federation.

Renders docs/architecture.png using the official GCP icon set.

    pip install diagrams   # requires graphviz: brew install graphviz
    python diagram.py

The diagram is deliberately organized around trust boundaries rather than
around services. The point of the build is which identity crosses which
boundary and what stops it, so the boxes are boundaries and the edges are
token exchanges.
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.security import IAMRole
from diagrams.gcp.devtools import ContainerRegistry
from diagrams.gcp.security import Iam, KMS, ResourceManager, SecretManager
from diagrams.gcp.storage import GCS
from diagrams.onprem.vcs import Github

GRAPH_ATTR = {
    "fontsize": "16",
    "labelloc": "t",
    "pad": "0.6",
    "splines": "spline",
    "nodesep": "0.7",
    "ranksep": "1.1",
    "bgcolor": "transparent",
}

# Short-lived credential exchanges.
TOKEN = {"color": "darkgreen", "style": "bold"}
# Paths that exist to be refused.
DENIED = {"color": "firebrick", "style": "dashed"}

with Diagram(
    "Workload Identity Federation on GCP",
    filename="docs/architecture",
    show=False,
    direction="LR",
    graph_attr=GRAPH_ATTR,
):
    with Cluster("GitHub"):
        actions = Github("Actions runner\nOIDC token")
        fork_pr = Github("Fork PR\nor other repo")

    with Cluster("AWS account"):
        aws_role_in = IAMRole("IAM role\n(calls GCP)")
        aws_role_out = IAMRole("gcp-federated-reader\n(assumed from GCP)")

    with Cluster("GCP organization"):
        with Cluster("Bootstrap project"):
            state = GCS("Terraform state\nno federated access")

        with Cluster("Workload project"):
            with Cluster("Workload Identity Federation"):
                pool = Iam("Pool provider\nattribute condition")
                principal = Iam("principalSet\nby repository / ref")

            with Cluster("Direct resource access"):
                bucket = GCS("Artifacts bucket")
                registry = ContainerRegistry("Artifact Registry")
                secret = SecretManager("Secret\nCMEK encrypted")

            with Cluster("Impersonation path"):
                deployer = Iam("gh-deployer\nservice account")

            key = KMS("Crypto key\nrotated 90d")
            policy = ResourceManager("Org policy\nno SA keys")
            caller = Iam("aws-caller\nservice account")

    # Path 1: token exchanged, no service account anywhere.
    actions >> Edge(label="OIDC token", **TOKEN) >> pool
    pool >> Edge(label="STS exchange", **TOKEN) >> principal
    principal >> Edge(label="read") >> bucket
    principal >> Edge(label="read") >> secret
    principal >> Edge(label="push on deploy ref") >> registry

    # Path 2: same token, exchanged for a service account instead.
    pool >> Edge(label="impersonate", style="dotted") >> deployer
    deployer >> Edge(style="dotted") >> registry

    # Refused at the door by the attribute condition.
    fork_pr >> Edge(label="wrong repo\nrefused", **DENIED) >> pool

    # Path 3: AWS to GCP.
    aws_role_in >> Edge(label="signed STS identity", **TOKEN) >> pool

    # Path 4: GCP to AWS.
    caller >> Edge(label="ID token\naud = SA unique ID", **TOKEN) >> aws_role_out

    # Controls.
    key >> Edge(label="encrypts", style="dashed") >> secret
    key >> Edge(style="dashed") >> registry
    policy >> Edge(label="key creation denied", **DENIED) >> deployer

    # State is out of reach of every federated identity above.
    principal >> Edge(label="no access", **DENIED) >> state
