# Create and IBM PowerVS and connect to your enterprise via site-to-site VPN for VPC

The same Power servers that power your business on premise are available in PowerVS workspaces in the IBM Cloud.  Businesses are using these on demand resources to explore new possibilities, enable development and test environments, <add more etc etc>.  Consumption based pricing means pay for only what you use and cloud elasticity allows for the expansion and contraction of your cloud footprint based on business needs.

This post will discuss connecting a PowerVS workspace to on premises using a site-to-site VPN for VPC.  The architecture is captured in Figure 1.

![vpc-transit-overview-power](images/transit-power-blog1-vpn.svg){: caption="Figure 1. Architecture diagram of the post" caption-side="bottom"}

`Figure 1`

The numbers in the figure are the steps to create the architecture:

1. Create a transit VPC and VPN
1. Create a PowerVS environment
1. Create a Transit Gateway and connect to both the transit VPC and PowerVS workspace
1. Create VPC Address Prefix in transit VPC
1. Create a transit VPC and VPN


# Create Power VS environment

workspace, SSH key, and Power Instance

# Create a Transit Gateway and connect to both the transit VPC and PowerVS workspace

Transit gateway

# Create VPC Address Prefix in transit VPC

The transit gateway needs to learn the CIDR blocks on each of the connections

# Troubleshoot