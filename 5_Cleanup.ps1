#-----------------------------------------------------------------------------------------
#Purpose: Clean functions to clean up accounts after the boot camp
#Author : Sriwantha Attanayake {sriwanth@amazon.com}
#Version: 1.1
#Date   : 16/Oct/2018
#-----------------------------------------------------------------------------------------

#A profile which has admin access to payer master account. 
#You first need to manually create an IAM user with access key and secret key and create a powershell profile
#using the command Set-AWSCredential -AccessKey xyz -SecretKey abc -StoreAs BootCampAdmin
#https://docs.aws.amazon.com/powershell/latest/userguide/specifying-your-aws-credentials.html
#This approach allows you to execute the script on your laptop or on an EC2 instance
$PAYER_ACCOUNT_ADMIN_PROFILE="LabAdmin"

#default region which this script will be executed
$DEFAULT_LOGIN_REGION="ap-southeast-2"

#This role is deployed to all the child accounts. We will then assume this role from master/payer account 
#to manage child accounts. The name of this role has to be same across all the child accounts: constant.
#Your student IAM policy should prevent deletion of this role 
$ACCOUNT_ADMIN_ROLE="LabOrgAdminRole"

#Current directory
$CURRENT_DIR=Split-Path $MyInvocation.MyCommand.Path

function CleanAccounts([string]$targetOrgName){
     <#
    .DESCRIPTION
       Clean all the resources (EC2 instances, EBS volumes, keys etc) deployed in accounts. 
    .PARAMETER targetOrgName
       Resouces will be clean for all the accounts under this organization
    #>
     
    $s=Read-Host -Prompt "BOOM!!!!!! Are you sure you want to flush all the account content?"
    if($s.Contains("n") -or $s.Contains("N")){
        exit;
    }elseif ($s -eq "YES") {
        
   
    Set-AWSCredential -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE
    Set-DefaultAWSRegion -Region $DEFAULT_LOGIN_REGION

  
    $accountInfo=Get-STSCallerIdentity
    Write-Output "------------------------------------------------------------"
    Write-Output ("Payer Account Login : "+$accountInfo.Arn)
    Write-Output ("Payer Account : "+$accountInfo.Account)
    Write-Output "------------------------------------------------------------"
    
    $rootId=Get-ORGRoot | Select-Object -ExpandProperty Id
    $childOrg=Get-ORGChild -ChildType ORGANIZATIONAL_UNIT -ParentId $rootId 
    $targetOrgId=$null
    #Search through all the root level OU and find an OU with the given name
    foreach($child in $childOrg){
       $currentOrg=Get-ORGOrganizationalUnit -OrganizationalUnitId $child.Id
       if($currentOrg.Name -eq $targetOrgName){
           Write-Output "Found an org $targetOrgName with Id "$currentOrg.Id.ToString()
           $targetOrgId=$child.Id
           break
       }
    }
    If($null -eq $targetOrgId){
        Write-Output "No organization with the name $targetOrgName was discovered. Please create this organization and accounts under this prior to starting this script"
        exit;
    }
    
    $studentAccountList=Get-ORGAccountForParent -ParentId $targetOrgId
    Write-Output ("Number of accounts : "+$studentAccountList.Length)

    foreach($studentAccount in $studentAccountList){
        $roleARN="arn:aws:iam::"+$studentAccount.Id+":role/$ACCOUNT_ADMIN_ROLE"
        Write-Host $roleARN
        $Creds = (Use-STSRole -RoleArn $roleARN -RoleSessionName "SetupAdminSession" -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE).Credentials
        Set-AWSCredential -AccessKey $Creds.AccessKeyId -SecretKey $Creds.SecretAccessKey -SessionToken $Creds.SessionToken
        $accountInfo=Get-STSCallerIdentity
        $region =Get-DefaultAWSRegion
        

        Write-Output "##################################################################"
        Write-Output ("## Student Account Login : "+$accountInfo.Arn)
        Write-Output ("## Student Account : "+$accountInfo.Account)
        Write-Output ("## Region : "+$region.Name+"-"+$region.Region)
        Write-Output "##################################################################"
       
      
        $autoScalingGroupList=Get-ASAutoScalingGroup 
        foreach($asGroup in $autoScalingGroupList){
            Write-Output ("Removing: Auto Scaling Group : "+$asGroup.AutoScalingGroupName)
            Remove-ASAutoScalingGroup -AutoScalingGroupName  $asGroup.AutoScalingGroupName -ForceDelete $true -Force
        }

        $ec2InstanceList=Get-EC2Instance
        foreach($ec2Reservation in $ec2InstanceList){
            foreach($ec2Instance in $ec2Reservation.Instances){
               Write-Output ("Removing EC2 instance : "+$ec2Instance.InstanceId)
               Remove-EC2Instance -InstanceId $ec2Instance.InstanceId -Force  
            }
        }

        $elbList=Get-ELBLoadBalancer
        foreach($elb in $elbList){
            Write-Output ("Removing ELB "+  $elb.LoadBalancerArn)
            Remove-ELBLoadBalancer -LoadBalancerArn $elb.LoadBalancerArn  -Force  
        }

        $elbList=Get-ELB2LoadBalancer
        foreach($elb in $elbList){
            Write-Output ("Removing ELB "+  $elb.LoadBalancerArn)
            Remove-ELB2LoadBalancer -LoadBalancerArn $elb.LoadBalancerArn  -Force  
        }

        $nicList=Get-EC2NetworkInterface
        foreach($nic in $nicList){
            Write-Output ("Removing NIC "+  $nic.NetworkInterfaceId)
            Remove-EC2NetworkInterface -NetworkInterfaceId $nic.NetworkInterfaceId -Force
        }

        $keyPairList=Get-EC2KeyPair
        foreach($key in $keyPairList){
            Write-Output ("Removing Key : "+  $key.KeyName)
            Remove-EC2KeyPair -KeyName $key.KeyName -Force
        }

        $launchConfigList=Get-ASLaunchConfiguration
        foreach($lc in $launchConfigList){
            Write-Output ("Removing Launch Configuration : "+  $lc.LaunchConfigurationName)
            Remove-ASLaunchConfiguration -LaunchConfigurationName  $lc.LaunchConfigurationName -Force
        }

        $ebsList=Get-EC2Volume
        foreach($ebs in $ebsList){
            Write-Output ("Removing EBS Volume : "+  $ebs.VolumeId)
            Remove-EC2Volume -VolumeId $ebs.VolumeId -Force
        }

        $publicIps=Get-EC2Address
        foreach($ip in $publicIps){
            Write-Output("Removing IP : "+$ip.PublicIp)
            Remove-EC2Address -AllocationId $ip.AllocationId -Force
        }
         
        $sgList=Get-EC2SecurityGroup | Where-Object {$_.GroupName -ne "default"}
        foreach($sg in $sgList){
            Write-Output("Removing SG : "+$sg.GroupId)
            Remove-EC2SecurityGroup -GroupId $sg.GroupId -Force
        }
 

       $elbTargetGroupList=Get-ELB2TargetGroup
       foreach($target in $elbTargetGroupList){
        Write-Output("Removing SG : "+$target.TargetGroupArn)
        Remove-ELB2TargetGroup -TargetGroupArn $target.TargetGroupArn -Force
       }



    $CFStackList=Get-CFNStackSummary | Where-Object {$_.StackStatus -ne "DELETE_COMPLETE"} | Sort-Object -Property CreationTime -Descending
    foreach($stack in $CFStackList){
        Write-Output("Removing CloudFormation stack : "+$stack.StackName)
        Remove-CFNStack -StackName $stack.StackName -Force
    }
 
    $ecrRepoList=Get-ECRRepository
    foreach($repo in $ecrRepoList){
        Write-Output("Removing ECR repo  : "+$repo.RepositoryName)
        Remove-ECRRepository -RepositoryName $repo.RepositoryName -IgnoreExistingImages $true  -Force 
    }
    $ecsClusterList=Get-ECSClusterList
    foreach($cluster in $ecsClusterList){
        $serviceList=Get-ECSClusterService -Cluster $cluster
        foreach($service in $serviceList){
            Write-Output("--Removing ECS Service  : "+$service)
            Remove-ECSService -Cluster $cluster -Enforce $true -Service $service -Force  
        }
        Write-Output("Removing ECS Cluster  : "+$cluster) 
        Remove-ECSCluster -Cluster $cluster  -Force
    }

    $ecsTaskDefList=Get-ECSTaskDefinitionList
    foreach($tDef in $ecsTaskDefList){
        Write-Output("Removing ECS Task Definition  : "+$tDef) 
        Unregister-ECSTaskDefinition -TaskDefinition $tDef -Force
    }  
    $cwAlarmList=Get-CWAlarm
    foreach($alarm in $cwAlarmList){
        Write-Output("Removing CW Alarm  : "+$alarm.AlarmName) 
        Remove-CWAlarm -AlarmName $alarm.AlarmName -Force
    }

    $cwRuleList=Get-CWERule
    foreach($rule in $cwRuleList){
        Write-Output("Removing CW Rule : "+$rule.Name)
        $ruleTargets=Get-CWETargetsByRule  -Rule $rule.Name
        foreach($rt in $ruleTargets){
            Write-Output("--Removing CW rule target "+$rt.Arn)
            Remove-CWETarget -Rule $rule.Name -Id $rt.Id   -Force  
        }

        Remove-CWERule -Name $rule.Name -Force
    }
    $cwLogGroupList=Get-CWLLogGroup
    foreach($lg in $cwLogGroupList){
        Write-Output("Removing CW log group : "+$lg.LogGroupName)
        Remove-CWLLogGroup -LogGroupName $lg.LogGroupName -Force
    }

    }
}
}

function ForceCleanWarmUpAccounts([string]$targetOrgName){


    Set-AWSCredential -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE
    Set-DefaultAWSRegion -Region $DEFAULT_LOGIN_REGION

    
    $accountInfo=Get-STSCallerIdentity
    Write-Output "------------------------------------------------------------"
    Write-Output ("Payer Account Login : "+$accountInfo.Arn)
    Write-Output ("Payer Account : "+$accountInfo.Account)
    Write-Output "------------------------------------------------------------"
    
    
    $rootId=Get-ORGRoot | Select-Object -ExpandProperty Id
    $childOrg=Get-ORGChild -ChildType ORGANIZATIONAL_UNIT -ParentId $rootId 
    $targetOrgId=$null
    #Search through all the root level OU and find an OU with the given name
    foreach($child in $childOrg){
       $currentOrg=Get-ORGOrganizationalUnit -OrganizationalUnitId $child.Id
       if($currentOrg.Name -eq $targetOrgName){
           Write-Output "Found an org $targetOrgName with Id "$currentOrg.Id.ToString()
           $targetOrgId=$child.Id
           break
       }
    }
    If($null -eq $targetOrgId){
        Write-Output "No organization with the name $targetOrgName was discovered. Please create this organization and accounts under this prior to starting this script"
        exit;
    }
    
    $studentAccountList=Get-ORGAccountForParent -ParentId $targetOrgId
    Write-Output ("Number of accounts : "+$studentAccountList.Length)

    foreach($studentAccount in $studentAccountList){
        $roleARN="arn:aws:iam::"+$studentAccount.Id+":role/$ACCOUNT_ADMIN_ROLE"
        Write-Host $roleARN
        $Creds = (Use-STSRole -RoleArn $roleARN -RoleSessionName "SetupAdminSession" -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE).Credentials
        Set-AWSCredential -AccessKey $Creds.AccessKeyId -SecretKey $Creds.SecretAccessKey -SessionToken $Creds.SessionToken
        $accountInfo=Get-STSCallerIdentity
        $region =Get-DefaultAWSRegion
        
        Write-Output "##################################################################"
        Write-Output ("Student Account Login : "+$accountInfo.Arn)
        Write-Output ("Student Account : "+$accountInfo.Account)
        Write-Output ("Region : "+$region.Name+"-"+$region.Region)
  
       
        $ec2InstanceList=Get-EC2Instance
        foreach($ec2Reservation in $ec2InstanceList){
            foreach($ec2Instance in $ec2Reservation.Instances){
               Write-Output ("Removing EC2 instance : "+$ec2Instance.InstanceId)
               Remove-EC2Instance -InstanceId $ec2Instance.InstanceId -Force  
            }
        }

        <#
        $nicList=Get-EC2NetworkInterface
        foreach($nic in $nicList){
            Write-Output ("Removing NIC "+  $nic.NetworkInterfaceId)
            Remove-EC2NetworkInterface -NetworkInterfaceId $nic.NetworkInterfaceId -Force
        }
      

        $ebsList=Get-EC2Volume
        foreach($ebs in $ebsList){
            Write-Output ("Removing EBS Volume : "+  $ebs.VolumeId)
            Remove-EC2Volume -VolumeId $ebs.VolumeId -Force
        }
   #>
       $CFStackList=Get-CFNStackSummary | Where-Object {$_.StackStatus -ne "DELETE_COMPLETE"} | Sort-Object -Property CreationTime -Descending
        foreach($stack in $CFStackList){
            Write-Output("Removing CloudFormation stack : "+$stack.StackName)
            Remove-CFNStack -StackName $stack.StackName -Force
        }
        Write-Output "##################################################################"
    }
}
 
function WindDownCF([string]$targetOrgName,[string]$cfStackName){
   <#
    .DESCRIPTION
       Roll back the given cloudformation stack
    .PARAMETER targetOrgName
    .PARAMETER cfStackName
     Name of the stack to roll back
    #>

    Set-AWSCredential -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE
    Set-DefaultAWSRegion -Region $DEFAULT_LOGIN_REGION

    
    $accountInfo=Get-STSCallerIdentity
    Write-Output "------------------------------------------------------------"
    Write-Output ("Payer Account Login : "+$accountInfo.Arn)
    Write-Output ("Payer Account : "+$accountInfo.Account)
    Write-Output "------------------------------------------------------------"
    
    
    $rootId=Get-ORGRoot | Select-Object -ExpandProperty Id
    $childOrg=Get-ORGChild -ChildType ORGANIZATIONAL_UNIT -ParentId $rootId 
    $targetOrgId=$null
    #Search through all the root level OU and find an OU with the given name
    foreach($child in $childOrg){
       $currentOrg=Get-ORGOrganizationalUnit -OrganizationalUnitId $child.Id
       if($currentOrg.Name -eq $targetOrgName){
           Write-Output "Found an org $targetOrgName with Id "$currentOrg.Id.ToString()
           $targetOrgId=$child.Id
           break
       }
    }
    If($null -eq $targetOrgId){
        Write-Output "No organization with the name $targetOrgName was discovered. Please create this organization and accounts under this prior to starting this script"
        exit;
    }
    
    $studentAccountList=Get-ORGAccountForParent -ParentId $targetOrgId
    Write-Output ("Number of accounts : "+$studentAccountList.Length)

    foreach($studentAccount in $studentAccountList){
        $roleARN="arn:aws:iam::"+$studentAccount.Id+":role/$ACCOUNT_ADMIN_ROLE"
        Write-Host $roleARN
        $Creds = (Use-STSRole -RoleArn $roleARN -RoleSessionName "SetupAdminSession" -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE).Credentials
        Set-AWSCredential -AccessKey $Creds.AccessKeyId -SecretKey $Creds.SecretAccessKey -SessionToken $Creds.SessionToken
        $accountInfo=Get-STSCallerIdentity
        $region =Get-DefaultAWSRegion
        
        Write-Output "##################################################################"
        Write-Output ("Student Account Login : "+$accountInfo.Arn)
        Write-Output ("Student Account : "+$accountInfo.Account)
        Write-Output ("Region : "+$region.Name+"-"+$region.Region)
  
       $CFStackList=Get-CFNStackSummary | Where-Object {$_.StackStatus -ne "DELETE_COMPLETE" } | Sort-Object -Property CreationTime -Descending
        foreach($stack in $CFStackList){
            Write-Output("Removing CloudFormation stack : "+$stack.StackName)
            Remove-CFNStack -StackName $stack.StackName -Force
        }
        Write-Output "##################################################################"
    }
}

WindDownCF -targetOrgName "PartnerLabOrg" -cfStackName "WarmUp"


