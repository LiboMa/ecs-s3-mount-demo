# ECS S3 Mount Setup Guide (ASG Version)

## Overview
Mount S3 bucket to ECS containers using mount-s3 on EC2 instances managed by Auto Scaling Group.

## Prerequisites
• S3 bucket: ecs-s3-test-test-bucket-hljs94ih
• VPC subnet: subnet-017213b7a972963da
• Security group: sg-05774d2b5ac5c9926
• Launch template: lt-0a015fb45dbe35d6a

## Step 1: Create IAM Roles

### ECS Task Execution Role
bash
aws iam create-role --role-name ecsTaskExecutionRole --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs-tasks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}'

aws iam attach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy


### ECS Instance Role
bash
aws iam create-role --role-name ecsInstanceRole --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}'

aws iam attach-role-policy --role-name ecsInstanceRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role

aws iam create-instance-profile --instance-profile-name ecsInstanceProfile
aws iam add-role-to-instance-profile --role-name ecsInstanceRole --instance-profile-name ecsInstanceProfile


### S3 Access Role
bash
aws iam create-role --role-name ecsS3AccessRole --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs-tasks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}'

aws iam put-role-policy --role-name ecsS3AccessRole --policy-name S3AccessPolicy --policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"],
    "Resource": ["arn:aws:s3:::ecs-s3-test-test-bucket-hljs94ih", "arn:aws:s3:::ecs-s3-test-test-bucket-hljs94ih/*"]
  }]
}'


## Step 2: Create ECS Cluster
bash
aws ecs create-cluster --cluster-name s3-mount-cluster --region us-west-2


## Step 3: Create Auto Scaling Group
bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name ecs-s3-asg \
  --launch-template "LaunchTemplateId=lt-0a015fb45dbe35d6a,Version=\$Latest" \
  --min-size 1 \
  --max-size 3 \
  --desired-capacity 1 \
  --vpc-zone-identifier subnet-017213b7a972963da \
  --health-check-type EC2 \
  --health-check-grace-period 300 \
  --region us-west-2


## Step 4: Create Task Definition
json
{
  "family": "s3-mount-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["EC2"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::ACCOUNT_ID:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::ACCOUNT_ID:role/ecsS3AccessRole",
  "containerDefinitions": [{
    "name": "s3-app-container",
    "image": "amazonlinux:2023",
    "essential": true,
    "mountPoints": [{
      "sourceVolume": "s3-volume",
      "containerPath": "/app/s3-data",
      "readOnly": false
    }],
    "command": ["/bin/bash", "-c", "ls -la /app/s3-data && echo 'S3 mounted successfully' && tail -f /dev/null"],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/s3-mount",
        "awslogs-region": "us-west-2",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }],
  "volumes": [{
    "name": "s3-volume",
    "host": {"sourcePath": "/mnt/s3-bucket"}
  }]
}


## Step 5: Register and Run Task
bash
# Create log group
aws logs create-log-group --log-group-name /ecs/s3-mount --region us-west-2

# Register task definition
aws ecs register-task-definition --cli-input-json file://task-definition.json --region us-west-2

# Run task
aws ecs run-task \
  --cluster s3-mount-cluster \
  --task-definition s3-mount-task \
  --launch-type EC2 \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-017213b7a972963da],securityGroups=[sg-05774d2b5ac5c9926]}" \
  --region us-west-2


## ASG Management Commands
bash
# Scale up
aws autoscaling set-desired-capacity --auto-scaling-group-name ecs-s3-asg --desired-capacity 2 --region us-west-2

# Scale down
aws autoscaling set-desired-capacity --auto-scaling-group-name ecs-s3-asg --desired-capacity 1 --region us-west-2

# Check ASG status
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ecs-s3-asg --region us-west-2


## Verification
bash
# Check ASG instances
aws autoscaling describe-auto-scaling-instances --region us-west-2

# Check cluster
aws ecs list-container-instances --cluster s3-mount-cluster --region us-west-2

# Check task
aws ecs list-tasks --cluster s3-mount-cluster --region us-west-2

# View logs
aws logs get-log-events --log-group-name /ecs/s3-mount --log-stream-name ecs/s3-app-container/TASK_ID --region us-west-2


## Key Changes from Manual EC2
• **Auto Scaling**: Instances managed by ASG for high availability
• **Launch Template**: Uses existing template lt-0a015fb45dbe35d6a
• **Scaling**: Can automatically scale based on demand
• **Health Checks**: ASG monitors instance health and replaces unhealthy instances

## Cleanup
bash
# Delete ASG
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name ecs-s3-asg --force-delete --region us-west-2

# Delete cluster
aws ecs delete-cluster --cluster s3-mount-cluster --region us-west-2
