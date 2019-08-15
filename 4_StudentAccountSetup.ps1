#-----------------------------------------------------------------------------------------
#Purpose: Creates IAM users in each accounts so that you can hand over username and password to students
#Author : Sriwantha Attanayake {sriwanth@amazon.com}
#Version: 1.4
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

#Student Group. Student IAM users that get created will be added to this group. Permission is granted to this group 
$STUDENT_GROUPNAME="StudentGroup"

#Username prefix of the IAMUser created for students
$STUDNET_USERNAME_PREFIX="student_"

#A user firendly password prefix added infront of every password generated
$PASSWORD_PREFIX="lab@"

#Number of students per account. If you want multiple students to use a given account you can increase this number. For example, if you 
# set this to 3, 3 IAM users will be created with 3 different usernames and passwords for a given account
$STUDENTS_PER_ACCOUNT=1

#Current directory
$CURRENT_DIR=Split-Path $MyInvocation.MyCommand.Path

function CleanGroups(){
     <#
    .DESCRIPTION
       Delete all groups. The context this function runs determines the account 
    #>
    foreach($g in Get-IAMGroupList -MaxItem 500){
        Write-Output ("Removing the group"+$g.GroupName)
        #You first need to remove all the users in the group and attached policies prior to removing it
        foreach($u in (Get-IAMGroup -GroupName $g.GroupName).Users){
            Remove-IAMUserFromGroup -GroupName $g.GroupName -UserName $u.UserName -Force
        }
        foreach($p in Get-IAMGroupPolicyList -GroupName $g.GroupName){
            Remove-IAMGroupPolicy -GroupName $g.GroupName -PolicyName $p -Force
        }
        foreach($p in Get-IAMAttachedGroupPolicyList -GroupName $g.GroupName){
            Unregister-IAMGroupPolicy -GroupName $g.GroupName -PolicyArn $p.PolicyArn -Force
        }
        Remove-IAMGroup -GroupName $g.GroupName -Force
    }
}
function CreateStudentGroup(){
     <#
    .DESCRIPTION
       Create a group to keep the students
    #>
    New-IAMGroup -GroupName $STUDENT_GROUPNAME
    $policyFiles=Get-ChildItem -Depth 1 -Path $CURRENT_DIR"\Data\StudentIAMPolicy" -Filter "*.json"

    #Size of the user policy exceeds AWS policy document character limit. Therefore the document is broken into multiple files
    foreach($pf in $policyFiles){
        #We assume the policy name to be the name of the file. Mindful about it. 
        $policyName=[System.IO.Path]::GetFileNameWithoutExtension($pf.Name)
        
        $policy=Get-IAMPolicyList |  Where-Object -Property PolicyName -eq $policyName         

        #Finally attch the policy to the user
        Write-Output ("Attaching the policy "+$policyName+" to the group "+$STUDENT_GROUPNAME)
        Register-IAMGroupPolicy -GroupName $STUDENT_GROUPNAME  -PolicyArn $policy.Arn
    }

    foreach($u in Get-IAMUserList | Where-Object {$_.UserName -Like "$STUDNET_USERNAME_PREFIX*" }){
        Add-IAMUserToGroup -GroupName $STUDENT_GROUPNAME -UserName $u.Username -Force
    }

}
function CleanPolicy(){
         <#
    .DESCRIPTION
       Remove all IAM policies that were previously attached. The names of the IAM policies comes from the names of the files
    #>
    $policyFiles=Get-ChildItem -Depth 1 -Path $CURRENT_DIR"\Data\StudentIAMPolicy" -Filter "*.json"

    #Size of the user policy exceeds AWS policy document character limit. Therefore the document is broken into multiple filesl
    foreach($pf in $policyFiles){
        #We assume the policy name to be the name of the file. Mindful about it. 
        $policyName=[System.IO.Path]::GetFileNameWithoutExtension($pf.Name)

        #Remove the existing policy
        $policy=Get-IAMPolicyList | Where-Object -Property PolicyName -eq $policyName
        if($null -ne $policy){
            #Before removing the policy you need to detach it from all the exiting entities
            foreach($pe in Get-IAMEntitiesForPolicy -PolicyArn $policy.Arn){
                foreach($pu in $pe.PolicyUsers){
                    Unregister-IAMUserPolicy -UserName $pu.UserName -PolicyArn $policy.Arn -Force
                }
                foreach($pr in $pe.PolicyRoles){
                    Unregister-IAMRolePolicy -RoleName $pr.RoleName -PolicyArn $policy.Arn -Force
                }
                foreach($pg in $pe.PolicyGroups){
                    Unregister-IAMGroupPolicy -GroupName $pg.GroupName -PolicyARn  $policy.Arn -Force
                }
            }

            #Remove all policy versions except the default, otherwise it will throw an error
            foreach($pvl in Get-IAMPolicyVersionList -PolicyArn $policy.Arn -MaxItem 10 | Where-Object -Property IsDefaultVersion -eq $false){
              Remove-IAMPolicyVersion -PolicyArn $policy.Arn -VersionId $pvl.VersionId -Force
            }
            #Finally remove the default policy
            Remove-IAMPolicy -PolicyArn $policy.Arn -Force
        }}
}
function CreatePolicy(){
    <#
    .DESCRIPTION
       Create new IAM policies out of the policies in the folder
    #>
    $policyFiles=Get-ChildItem -Depth 1 -Path $CURRENT_DIR"\Data\StudentIAMPolicy" -Filter "*.json"

    #Size of the user policy exceeds AWS policy document character limit. Therefore the document is broken into multiple files
    foreach($pf in $policyFiles){
        #We assume the policy name to be the name of the file. Mindful about it. 
        $policyName=[System.IO.Path]::GetFileNameWithoutExtension($pf.Name)

        #Remove the existing policy
        $policy=Get-IAMPolicyList | Where-Object -Property PolicyName -eq $policyName

        $policyContent=Get-Content $pf.FullName -Raw

        Write-Output "Creating a new policy "$policyName
        New-IAMPolicy -PolicyName $policyName -PolicyDocument $policyContent -Force 
    }
}
function CleanUsers(){
    <#
    .DESCRIPTION
       #Remove all users
    #>
     
    foreach($u in Get-IAMUserList -MaxItem 1000){
        #You need to first remove access keys/profiles/inline policies/managed policies attached to the user & remove from groups before removing the user
        Write-Output "Trying to get login profile. If no login profile is attached this will through an error.  You can safely ignore the error"
        try{
            $lp=Get-IAMLoginProfile -UserName $u.UserName 
            Write-Host $lp.UserName
            if($null -ne $lp){
             Remove-IAMLoginProfile   -UserName $u.UserName -Force
            }
        }catch{
            $ErrorMessage = $_.Exception.Message
            $FailedItem = $_.Exception.ItemName
            Write-Output $ErrorMessage
        }

        foreach ($ak in Get-IAMAccessKey -UserName $u.UserName) { 
                Remove-IAMAccessKey -AccessKeyId $ak.AccessKeyId -UserName $u.UserName -Force 
        }

        foreach($inlinePolicy in Get-IAMUserPolicyList -UserName $u.UserName){
            Remove-IAMUserPolicy -PolicyName $inlinePolicy.PolicyName -UserName $u.UserName -Force
        }

        foreach($attachedManagedPolicy in Get-IAMAttachedUserPolicyList -UserName $u.UserName){
            
            Unregister-IAMUserPolicy -PolicyArn $attachedManagedPolicy.PolicyArn -UserName $u.UserName -Force
        }
        foreach($ug in Get-IAMGroupForUser -UserName $u.UserName){
            Remove-IAMUserFromGroup -GroupName $ug.GroupName -UserName $u.UserName -Force
        }

        Write-Output ("Removing user "+$u.UserName)
        Remove-IAMUser -UserName $u.UserName -Force
    }
}

function CleanStudentAccountLogins([string] $targetOrgName){
    <#
    .DESCRIPTION
       Iterate accross all the accounts under the target organization and remove all the IAM users,groups & permissions
    .PARAMETER targetOrgName
       All student accounts under this organization will be affected 
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
    $Creds = (Use-STSRole -RoleArn $roleARN -RoleSessionName "SetupAdminSession" -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE).Credentials
    Set-AWSCredential -AccessKey $Creds.AccessKeyId -SecretKey $Creds.SecretAccessKey -SessionToken $Creds.SessionToken
    $accountInfo=Get-STSCallerIdentity
    Write-Output "------------------------------------------------------------"
    Write-Output ("Student Account Login : "+$accountInfo.Arn)
    Write-Output ("Student Account : "+$accountInfo.Account)

    CleanPolicy
    CleanUsers
    CleanGroups
    Write-Output "------------------------------------------------------------"
}
}
function CreateStudentUsers([string] $targetOrgName){
     <#
    .DESCRIPTION
       Create IAM users to be hand over to students
    #>

    #where to save the generated passwords?
    $studnetPasswords=$CURRENT_DIR+"\Data\Output\StudentCredentials_"+$targetOrgName+".txt"
    if (-not (Test-Path $studnetPasswords)) {
        "LoginURL,Account,UserName,Password" | Out-File -FilePath $studnetPasswords
    }
    
    for($i=1;$i -le $STUDENTS_PER_ACCOUNT;$i++){
        $studnetUserName="{0}{1}" -f $STUDNET_USERNAME_PREFIX,$i

        Write-Output ("Creating a new user "+$studnetUserName)
        #Create a new IAM user and assign a login profile
        New-IAMUser -UserName $studnetUserName -Force
        $password=$PASSWORD_PREFIX+[Guid]::NewGuid().ToString("N").SubString(0,12).ToLower()
        New-IAMLoginProfile -UserName $studnetUserName -Password $password -Force -PasswordResetRequired $false 
    
        $url="https://{0}.signin.aws.amazon.com/console?region={1}" -f $accountInfo.Account,$DEFAULT_LOGIN_REGION
    
        Add-Content -Value $url -NoNewline  -Path $studnetPasswords
        Add-Content -Value (","+$accountInfo.Account) -NoNewline  -Path $studnetPasswords
        Add-Content -Value (","+$studnetUserName) -NoNewline  -Path $studnetPasswords
        Add-Content -Value (","+$password)  -Path $studnetPasswords
    }
}

function CreateStudentAccountLogins([string] $targetOrgName){
    <#
    .DESCRIPTION
       Iterate accross all the accounts under the target organization and create IAM users to login
    .PARAMETER targetOrgName
       IAM users will be created under all the accounts under this organization 
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
    $Creds = (Use-STSRole -RoleArn $roleARN -RoleSessionName "SetupAdminSession" -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE).Credentials
    Set-AWSCredential -AccessKey $Creds.AccessKeyId -SecretKey $Creds.SecretAccessKey -SessionToken $Creds.SessionToken
    $accountInfo=Get-STSCallerIdentity
    Write-Output "------------------------------------------------------------"
    Write-Output ("Student Account Login : "+$accountInfo.Arn)
    Write-Output ("Student Account : "+$accountInfo.Account)

    CleanPolicy
    CleanUsers
    CleanGroups

           
    CreatePolicy
    CreateStudentUsers -targetOrgName $targetOrgName
    CreateStudentGroup
    Write-Output "------------------------------------------------------------"
}
}

CreateStudentAccountLogins -targetOrgName "PartnerLabOrg"



 