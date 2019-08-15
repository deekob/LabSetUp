#-----------------------------------------------------------------------------------------
#Purpose: Helper functions to setup an AWS organization and apply service control policies related to the boot camp. 
#Author : Sriwantha Attanayake {sriwanth@amazon.com}
#Version: 1.8
#Date   : 16/Oct/2018
#-----------------------------------------------------------------------------------------

#A profile which has admin access to payer master account. 
#You first need to manually create an IAM user with access key and secret key and create a powershell profile
#using the command Set-AWSCredential -AccessKey xyz -SecretKey abc -StoreAs BootCampAdmin
#https://docs.aws.amazon.com/powershell/latest/userguide/specifying-your-aws-credentials.html
#This approach allows you to execute the script on your laptop or on an EC2 instance
$PAYER_ACCOUNT_ADMIN_PROFILE="LabAdmin"

#Default region which this script will be executed
$DEFAULT_LOGIN_REGION="ap-southeast-2"

function CreateOrg([string]$targetOrgName){
    <#
    .DESCRIPTION
       Creates an Organization unit under AWS organization. 
       Root organization must exits and service control policies should be already enabled for root organization
    .PARAMETER targetOrgName
       Name of the target organizatoin to be created. Policies will be attached to this organization. 
    .EXAMPLE
        CreateOrg -targetOrgName TestOrg
    #>

    Set-AWSCredential -ProfileName  $PAYER_ACCOUNT_ADMIN_PROFILE
    Set-DefaultAWSRegion -Region $DEFAULT_LOGIN_REGION

    #DENY_ALL.json will be used temporarily during policy change. Note that you can't detach all the attached policy in an organization. You need to have at least one policy attached.
    $DENY_ALL_NAME="DENY-ALL"


    $currentDir=Split-Path $PSCommandPath


    #The character length of the full policy exceeds the AWS permitted limits. 
    #Therefore, the policy is broken into a few json files.  
    #Get all SCP. These policies gives just enough permission for the boot camp  
    $policyFiles=Get-ChildItem -Depth 1 -Path $currentDir"\Data\AWSOrganizationSCP" -Filter "*.json"
    $policyIdSet=New-Object System.Collections.Generic.List[System.String]

    foreach($pf in $policyFiles){
        #We assume the policy name to be the name of the file. Mindful about it. 
        $policyName=[System.IO.Path]::GetFileNameWithoutExtension($pf.Name)

        $policyId=Get-ORGPolicyList -Filter SERVICE_CONTROL_POLICY |  Where-Object {$_.Name -eq $policyName} | Select-Object -ExpandProperty Id 
        $policyContent=Get-Content $pf.FullName -Raw

        If($null -ne $policyId){
        Write-Output "Updating the policy $policyName : $policyId"
        Update-ORGPolicy -Name $policyName -Description "AWS Lab SCP" -PolicyId $policyId -Content $policyContent
        }else{
        Write-Output "Creating a new policy "$policyName
        New-ORGPolicy -Type SERVICE_CONTROL_POLICY -Name $policyName -Content $policyContent -Description "AWS Lab SCP"
        $policyId=Get-ORGPolicyList -Filter SERVICE_CONTROL_POLICY |  Where-Object {$_.Name -eq $policyName} | Select-Object -ExpandProperty Id 
        }

        if($policyName -ne $DENY_ALL_NAME){
        $policyIdSet.Add($policyid);
        } 
    }

    $denyAllPolicyId=Get-ORGPolicyList -Filter SERVICE_CONTROL_POLICY |  Where-Object {$_.Name -eq $DENY_ALL_NAME} | Select-Object -ExpandProperty Id 
    $fullAccessPolicyId=Get-ORGPolicyList -Filter SERVICE_CONTROL_POLICY |  Where-Object {$_.Name -eq "FullAWSAccess"} | Select-Object -ExpandProperty Id 


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
    "Creating a new organization unit $targetOrgName at root level"
    $workshopOrg=New-ORGOrganizationalUnit -Name $targetOrgName -ParentId $rootId
    $targetOrgId= $workshopOrg.Id
    }

    #---------------------------------------------------------
    #At this stage you should have an OU to apply permission
    #---------------------------------------------------------

    #find currently attached policies
    $attachedPolicies=Get-ORGPolicyForTarget -TargetId $targetOrgId -Filter SERVICE_CONTROL_POLICY
    #first set temporaly set the deny_all policy - temp
    Add-ORGPolicy -PolicyId $denyAllPolicyId -TargetId  $targetOrgId

    #detached all current policies
    foreach($ap in $attachedPolicies){
        Write-Output "Refreshing $TARGET_ORG_NAME : $targetOrgId by detaching the policy "$ap.Name ":" $ap.Id 
        Dismount-ORGPolicy -PolicyId $ap.Id -TargetId $targetOrgId
    }

    #attach all our policies
    foreach($pi in $policyIdSet){
        Write-Output "Attaching  $TARGET_ORG_NAME : $targetOrgId by detaching the policy "$ap.Name ":" $ap.Id 
        Add-ORGPolicy -PolicyId $pi -TargetId  $targetOrgId
    }

    #now remove the temporarily attached  DENY_ALL policy
    Dismount-ORGPolicy -PolicyId $denyAllPolicyId -TargetId $targetOrgId
    try{
    Dismount-ORGPolicy -PolicyId $fullAccessPolicyId -TargetId $targetOrgId
    }catch{}
}


CreateOrg -targetOrgName "PartnerLabOrg"






