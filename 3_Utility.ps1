#-----------------------------------------------------------------------------------------
#Purpose: Helper functions/unility functions
#Author : Sriwantha Attanayake {sriwanth@amazon.com}
#Version: 1.6
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

#current script path
$CURRENT_DIR=Split-Path $MyInvocation.MyCommand.Path




function ExeCFOnOrgAccounts([string]$targetOrgName,[string]$stackName,[string]$cloudformationTemplate){
    <#
    .DESCRIPTION
       Execute a given cloudformation template for all the accounts under a given organization unit
    .PARAMETER stackName
       Name of the cloudformation statck. This has to be unique.
    .PARAMETER cloudformationTemplate
       file name of the cloudformation template. The cloudformation templates are kept under
       \Data\Input\  
    .EXAMPLE
        ExeCFOnOrgAccounts -targetOrgName "TestOrg" -stackName "BasicLabSetup1" -cloudformationTemplate "BasicLabSetup.template"

        The above command will execute the cloudformation template \Data\Input\BasicLabSetup.template for all the accounts
        under TestOrg. The stack name will be called BasicLabSetup1
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

    $templateFile=$CURRENT_DIR+"\Data\Input\"+$cloudformationTemplate
    $policyContent=Get-Content $templateFile -Raw

    foreach($studentAccount in $studentAccountList){
        $roleARN="arn:aws:iam::"+$studentAccount.Id+":role/$ACCOUNT_ADMIN_ROLE"
        $Creds = (Use-STSRole -RoleArn $roleARN -RoleSessionName "SetupAdminSession" -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE).Credentials
        Set-AWSCredential -AccessKey $Creds.AccessKeyId -SecretKey $Creds.SecretAccessKey -SessionToken $Creds.SessionToken
        $accountInfo=Get-STSCallerIdentity
        $region =Get-DefaultAWSRegion
        

        Write-Output "##################################################################"
        Write-Output ("Student Account Login : "+$accountInfo.Arn)
        Write-Output ("Student Account : "+$accountInfo.Account)
        Write-Output ("Region : "+$region.Name+"-"+$region.Region)
        Write-Output ("Creating the stack "+$stackName)
        #New-CFNStack -StackName $stackName  -OnFailure ROLLBACK -ResourceType "AWS::*"   -TemplateBody $policyContent -TimeoutInMinutes 10 -Force 

        New-CFNStack -StackName $stackName  -OnFailure ROLLBACK  -Capability CAPABILITY_NAMED_IAM   -TemplateBody $policyContent -TimeoutInMinutes 10 -Force 
        Write-Output "##################################################################"

    }
}


function ShareAMI([string]$targetOrgName){
    <#
    .DESCRIPTION
       Share the lab AMI across multple accounts. 
    .PARAMETER targetOrgName
       To which accounts you want to share the lab AMI
    .EXAMPLE
        ShareAMI -targetOrgName "TestOrg"  

        The above command will share the lab AMI (hard coded in the function) across all the accounts under TestOrg
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

        Edit-EC2ImageAttribute -ImageId "ami-0121039cd1bde9330" -Attribute launchPermission -OperationType add -UserId $studentAccount.Id
        Write-Output ("Adding "+$studentAccount.Id)
    }
}

ExeCFOnOrgAccounts -targetOrgName "PartnerLabOrg" -stackName "WarmUp" -cloudformationTemplate "Warmup.template"
#ExeCFOnOrgAccounts -targetOrgName "TestOrg" -stackName "BasicLabSetup" -cloudformationTemplate "BasicLabSetup.template"




