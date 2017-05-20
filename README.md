# Structure of this document

# Global Environment Variables

The environment variables are assumed to be present when any of the commands in this document are run.

I wrote an script called env that describes all of the environment variables and should be sourced before running any of the commands below.

# Deployment of the K8 cluster on AWS

When you run this, you have no idea if it will work. No this is not because I set this up wrong or did not test it well enough. Simply put, I can run the exact same steps and get different outcomes. I'm not sure what magic is going on at AWS or even with the tools I use. If it does not work, just try it again and it might work Which is why I do not provide a script or Makefile to deploy a cluster.

This section goes through how to deploy a k8 cluster on AWS. There are three sections. The Pre-requisites goes through everything you need to do before calling `kops`, which sets up the actual cluster on AWS. Deployment with Kops is how to invoke `kops`. Validation goes though the steps involved with checking that the deployment is ready for production use.  

## Pre-requisites

Keep in mind that without an account, none of the other steps can be done. Although you can install the tools beforehand.

### Create AWS account

You can get free credit for an AWS account by getting access to the github student pack bundle. I think they will let academics also use their uni email to get some free credit.

After account creation, you can begin the next steps

### Create IAM role on AWS

After you create your account you have credentials to what is considered the master of the account, but in general you don't need that kind of power. So instead AWS has IAM that lets you create roles with restricted privileges. Back when I first created my AWS account IAM took you through a wizard to create your administrator account which you should always use instead of the master.

Once you have done that, go ahead and create access keys for the admin account from the IAM console. You will need them to setup the aws tool. 

### Local Tools

#### aws tool

This install commands assume you have `brew` installed. If not go ahead and go to their website for install instructions. 

To install aws you can use `pip` if you are not on a mac, otherwise just use `brew`.

```
brew install awscli
```

The version this project tested with is: `aws-cli/1.11.13 Python/2.7.10 Darwin/16.5.0 botocore/1.4.70`

To configure it with your credentials run:

```
aws configure
```

#### kubectl tool

Please see the online docs: [kubectl install instructinos](https://kubernetes.io/docs/tasks/tools/install-kubectl/).

The version that this project tested with is: 

```
{
	Major:"1", 
	Minor:"5", 
	GitVersion:"v1.5.4", 
	GitCommit:"7243c69eb523aa4377bce883e7c0dd76b84709a1", 
	GitTreeState:"clean", 
	BuildDate:"2017-03-08T02:50:34Z", 
	GoVersion:"go1.8", 
	Compiler:"gc", 
	Platform:"darwin/amd64"
}
```

#### kops tool

Your AWS Acces Key ID and AWS Secret Access Key come from the access key you got from the previous step. The default region is not important, but you can set to ap-northeast-2. However, it is important to set the default output format to json. Some of the scripts rely on that aspect.

Next you need to install `kops`, either by downloading a release or running

```
brew install kops
```

The version this project was tested with is: `Version 1.5.3`

### Domain on AWS

You need to have a domain registered on Route53 in AWS. This domain is used for both ingress into the k8 cluster and internal communication in the cluster, so you need to have one before you can deploy the cluster. In the route53 interface they give you an option to both buy a domain and have it automatically managed by them.

![](aws-route53.png)

The next setup is to create certificates for the domain. Us the AWS Certificate Manager to create a wild card certificate for the domain. This is important since we need to create a variable number of sub domains, all of which need a valid certificate. You can use something like lets encrypt, but that would mean you need to generate a certificate for each subdomain.

### SSH keypair

Next you need to upload your rsa public key to AWS so `kops` can put in on the actual virtual machines it will create. To create a new key:

```
ssh-keygen -t rsa -b 4096 -f k8-$REGION.pem
```

Note: I like to call the key the name of the region, example: k8s-ap-southeast-2

You can upload your public key in the EC2 service under Key Pairs.

### S3 Bucket

`kops` needs an S3 bucket to store the `terraform` code and k8 config files. 

```
aws s3 mb $BUCKET --region $REGION 
```

## Deployment with Kops 

You will need to source the environment variables in the same shell you run this command in:

Note: This command will replace your ~/.kube/config file. So if you have previously setup minicube, you will lose your credentials.

```
kops create cluster \
			--yes \
			--zones $ZONES \
			--ssh-public-key $PUBLIC_KEY_PATH \
			$NAME
```

You might get this kind of error:

```
error determining default DNS zone: No matching hosted zones found for "<your url>"; please create one (e.g. "<your url>") first
```

I have no idea why this happens, but if you deploy the cluster again, a few times, it just works.

To delete the cluster, say if something goes wrong like above, run this:

```
kops delete cluster --yes $NAME
```

Note: sometimes you need to delete the cluster even if nothing actually deployed. Not really sure what state is kept when `kops` fails, but it can prevent `kops` from working correctly.

## Validation

Validation is done by running:

```
kops validate cluster $NAME
```

That command outputs a few others that you can try. However, you need to wait quite awhile before they will tell you the cluster works. For me it took about 20min before the cluster was ready to respond. So if it does not work, just wait. For example if you see:

```
cannot get nodes for "<your url>": Get https://api.<your url>/api/v1/nodes: dial tcp <some ip>:443: i/o timeout
```

Then may mean your cluster is not yet setup and you just need to wait or everything is broken and you will have no idea why.

# Deploying services on k8

These tend to be a lot more predictable. Either they work flawlessly or throw sometimes useful errors. As such I have put them in Makefiles to speed up deployment and reversals. I will go into detail about how each one works, but at the start of each section I have a summary of just the commands you need to run to deploy that part.

## Default-backend service and Nginx/Warp

This is the service that handles load-balancing and internal routing. It creates the Elastic Load Balancer which all traffic goes through. This is important since that load balancer handles the certificates. Plus this also has the default backend which is part of the internal routing.

The service is split access two different deployments and services, one is the Nginx/warp instance and the other is a image from google. This means the `nginx-ingress-controller-deployment.yaml' is actually made up of two images, the Nginx and the Wrap image. The `nginx-ingress-controller-service.yaml` creates the load balancer with the certs on AWS. While the 'default-backend-deployment.yaml` and `default-backend-service.yaml` is responsible for internal routing.

Note: Services in k8 are how other services "discover" each other. It provides an abstracted view of what a deployment does.

Note: The Nginx might need some changes to the config so swagger-ui works correctly. As of now I can only get swagger-ui to accept the swagger spec from PostgREST if it is run locally.

Note: The Warp instance's purpose is to force ssl, it redirects all HTTP traffic to HTTPS.

Note: find out if when you send a request with a password over HTTP, does the request get rejected before the password is sent?

Note: The traffic between the ELB and the rest of the cluster should be in HTTP, I think I have taken the necessary precautions, but I should ask about it when I get the chance.

### Setup

You have to lookup the arn in the AWS Certificate Manager online, ![example](aws-cert-manager-console.png).

Once you get to the place in the image above click on your cert and in the drop down you will see the ARN. Put that into your `env` file as `SSL_CERT_ARN`.

### Summary of deployment commands

To Deploy, in the k8/ingress directory run:

```
make
```

To remove, in the same directory run:

```
make clean
```

## Postgresql

### Summary of deployment commands

## PostgREST

Note: the `AWS_HOST_ID` env uses `DOMAINNAME` to figure out which of the `hostedZones` is the right one. Just make sure the `DOMAINNAME` is only the domain. For example: gasworktesting **NOT** gasworktesting.com

Note: The `ELB` env variable is filled with the first elastic load balancer it finds. I might be able to do something where I ask k8 what vpc the cluster is in and use that to filter the results, but for now just keep this is mind.

### Summary of deployment commands

## Swagger-UI
