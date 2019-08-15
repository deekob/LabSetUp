#-----------------------------------------------------------------------------------------
#Purpose: Helper functions to bulk create AWS accounts under the payer account.
#Author : Sriwantha Attanayake {sriwanth@amazon.com}
#Version: 1.5
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

#Current working folder
$CURRENT_DIR=Split-Path $MyInvocation.MyCommand.Path


#This role will be deployed to all the child accounts. We will then assume this role from master/payer account 
#to manage child accounts. The name of this role has to be same across all the child accounts: constant.
#Your student IAM policy should prevent deletion of this role 
$ACCOUNT_ADMIN_ROLE="LabOrgAdminRole"

function CreateOrgAccount([string]$prefix,[string]$domainName,[int]$startId,[int]$endId){
    <#
    .DESCRIPTION
       Create AWS accounts in bulk under an AWS organization
    .PARAMETER prefix
       Prefix to be used when creating an account. For example, if the prefix is mylab- the account names will 
       be in the format mylab-1 mylab-2 mylab-3 ... and the account emails will be in the format mylab-1@domain.com mylab-2@domain.com

       If your amazon username is xyz you usually have an email address like xyz@amazon.com
       In addition any email that goes like xyz+{suffix}@amazon.com will also routed to your mail box. 
       For example all following are you email addresses
       xyz+abc1@amazon.com xyz+tt@amazon.com xyz+123@amazon.com
    .PARAMETER domainName
       domain portion of the the email address
    .PARAMETER startId
        The start number of the Id
    .Parameter endId
        End number of the id
    .EXAMPLE
        CreateOrgAccount -prefix "myusername+labenv-" -domainName "amazon.com" -startId 2 -endId 100

        The above command will create 98 accounts with account email addresses 
        myusername+labenv-2@amazon.com,myusername+labenv-3@amazon.com,...,myusername+labenv-100@amazon.com,
    #>
    
    Set-AWSCredential -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE
    Set-DefaultAWSRegion $DEFAULT_LOGIN_REGION

    for($i=$startId;$i -le $endId;$i++){
        $accountName="$prefix$i"
        $email="$accountName@$domainName"
        Write-Output ("Creating the account"+$accountName)
        New-ORGAccount -AccountName $accountName -Email $email -IamUserAccessToBilling "Allow" -RoleName $ACCOUNT_ADMIN_ROLE -Force
        #You can't execute New-OrgAccount in quick successions. So sleep a while before executing it again.
        Start-Sleep -Seconds 10
    }
}

function MoveAccounts([string]$sourceOrgName,[string]$targetOrgName,[string]$searchPrefix,[int]$startId,[int]$endId){
    <#
    .DESCRIPTION
       Bulk move AWS accounts from source organization to a given target organization unit. 
       The source,target organization unit should be directly under the root organization. Source and target can also be Root
    .PARAMETER sourceOrgName
       Name of source organization to search for accounts. Source organization can be Root or any organization unit directly under root
    .PARAMETER targetOrgName
       Name of target organization as the destination. target organization can be Root or any organization unit directly under root
    .PARAMETER searchPrefix
       Accounts starting with this search prefix will be matched and moved
    .PARAMETER startId
       start id of the accout name
    .PARAMETER endId
        end id of the account name
    .EXAMPLE
        MoveAccounts -targetOrgName "TestOrg" -searchPrefix "myusername+labenv-" -startId 2 -idEnd 50

        The above command will move 48 accounts with account email addresses 
        myusername+labenv-2@amazon.com,myusername+labenv-3@amazon.com,...,myusername+labenv-50@amazon.com
        to a target organization called TestOrg
    #>
    Set-AWSCredential -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE
    Set-DefaultAWSRegion $DEFAULT_LOGIN_REGION
    
    $rootId=Get-ORGRoot | Select-Object -ExpandProperty Id
    $sourceOrgId=$null
    $targetOrgId=$null

    $childOrg=Get-ORGChild -ChildType ORGANIZATIONAL_UNIT -ParentId $rootId 
    if($sourceOrgName -eq "Root"){
        $sourceOrgId=$rootId
    }else{
        #Search through all the root level OU and find an OU with the given name
        foreach($child in $childOrg){
            $currentOrg=Get-ORGOrganizationalUnit -OrganizationalUnitId $child.Id
            if($currentOrg.Name -eq $sourceOrgName){
                Write-Output "Found an org $sourceOrgName with Id "$currentOrg.Id.ToString()
                $sourceOrgId=$child.Id
                break
               }
           }
    }

    if($targetOrgName -eq "Root"){
        $targetOrgId=$rootId
    }else{
        #Search through all the root level OU and find an OU with the given name
        foreach($child in $childOrg){
            $currentOrg=Get-ORGOrganizationalUnit -OrganizationalUnitId $child.Id
            if($currentOrg.Name -eq $targetOrgName){
                Write-Output "Found an org $targetOrgName with Id "$currentOrg.Id.ToString()
                $targetOrgId=$child.Id
                break
               }
           }
    }



    If($null -eq $targetOrgId){
       "Can't find the  $targetOrgName at root level"
        exit;
    }
    
    If($null -eq $sourceOrgId){
        "Can't find the  $sourceOrgName at root level"
         exit;
     }

     if($sourceOrgId -eq $targetOrgId){
        "Source and the target orgs are the same"
        exit;
     }

    $accountList=Get-ORGAccountForParent -ParentId $sourceOrgId
    for($i=$startId;$i -le $endId;$i++){
        $accountName=$searchPrefix+$i
        $account=$accountList | Where-Object {$_.Name -eq $accountName} 
        Write-Output ("Moving "+$account.Id)
        Move-ORGAccount -AccountId $account.Id  -DestinationParentId $targetOrgId -SourceParentId $sourceOrgId -Force
        Start-Sleep -Seconds 10
    }
}


#CreateOrgAccount -prefix "person+testlab-" -domainName "amazon.com" -startId 10 -endId 60
#MoveAccounts -sourceOrgName "Root" -targetOrgName "PartnerLabOrg" -searchPrefix "person+testlab-"  -startId 10 -endId  60
#MoveAccounts -sourceOrgName "TestOrg" -targetOrgName "Manila-20-Nov-2018" -searchPrefix "person+testlab-"  -startId 21 -endId  40



