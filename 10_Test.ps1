#-----------------------------------------------------------------------------------------
#Purpose: Test/status test methods
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
$ACCOUNT_ADMIN_ROLE="LabOrgAdminRole"

#default region which this script will be executed
$DEFAULT_LOGIN_REGION="ap-southeast-2"

function STSTokenDecorder(){
         <#
    .DESCRIPTION
       if you get a permission denyed message and want to decode the STS Authorizaton message, use this to find the issue.  
    #>
    $accountId="358209534311"
    $roleARN="arn:aws:iam::"+$accountId+":role/NinjaOrgAdminRole"

    $Creds = (Use-STSRole -RoleArn $roleARN -RoleSessionName "SetupAdminSession" -ProfileName $PAYER_ACCOUNT_ADMIN_PROFILE).Credentials
    Set-DefaultAWSRegion -Region $DEFAULT_LOGIN_REGION
    Set-AWSCredential -AccessKey $Creds.AccessKeyId -SecretKey $Creds.SecretAccessKey -SessionToken $Creds.SessionToken

    $accountInfo=Get-STSCallerIdentity
    Write-Output "------------------------------------------------------------"
    Write-Output ("Account Login : "+$accountInfo.Arn)
    Write-Output ("Account : "+$accountInfo.Account)
    Write-Output "------------------------------------------------------------"
    $messageToDecode="-D-jzFJ85pc3-t00_kh8AG_49qhLZ3fuX_p9Dx7udpDfZ5Di0umZpMWCvQ57mlgVMov4kZRE_LnldeMuDf1Chd8LRP6H_capbaGWBq_qABTPyU0TEPBExKGuyZwiGxSKqrQaV1L9lX5shnZ5B66zp7Clzb1vPt_u0O5BFt-GCCy19VEzbC50WR-Q6OBcEGizrS5_-6AJkMRBUs_L2rwA36clUyZ2SWqgah0KnyhWqkMXrsecvUm3skGxi3pe79Z12wdtB-KmXVArkS6CNtS5Yw4Dr8GiYF-eymT0pS5DL5D5vpz1ps1VwmltEuIYo3QnNAqkrD1hp4WrbgSGbs9EI_enJ3ab4_Tp2dcM9cSEsUe1yeVZMu27r91QKe8irQiS8fNc8LKy5KUafPMmQ_i7LMNXUCePwd7IBONNECxCfELTeuZedQSq_MgpIc78lG0cCfqV2HZty-q6Ye7zJycvc-xnc74Sh1NfkPK-NUqbJTND_RmN2qglxqYOirYrqucTQmtTgmLdA50Dg6s4lkiCSD3dKwPZziIvjkQJeyuVC0UHcsjFC4zMUyqoCv0syjWK1Hsx_8_fM_YfCGUfAIUWh3q378o95mBCeJBRK5SYhasyU5KqrV8L7zRgo_H5oOWBj7YtWCro3Gz_IXTNA2teyIgBOx_0H_KhYcImPgq6jT64vvh5T-1O9Lh5qsG83kjMkVudKIufNeFE10Aidf3vliljgEKK3_i8mp-ci_MSzFU4iYykQ_5y-WvSgduoBABH44NFl7f96VfgoWPXdJHqTxM8I92i6IJLYpUtB4KxBka9_5BvXw_iOYThtmGjhAFl3I_UAVVS9p_zDlJ9QFONJUMXuVNbXLIVOLGswYoThLoQqKsE5Ke0V8ooMUsHGwXTgJjKBb3zquwUNB5u0wIyrAeO42bkoE3pDlpIY23EDbOs_b8lLZJfcQXWgpDdQaosnqythQVFKK-7arYFtfyEjyQ4grJrDkqJWxMdNPhdkjLJCToh22gQMtzyAWcixZbbCExaG4-cMI0clqrgYU-YBR3_dsDzsFfE0uwMgxsluAvaq7X7M_siWKyPamqyrHck7sOwlYncCwOAi0mERCV7FZEAil-Qf8_aqUrN2JH66-94dr_4EOe-uJkJZifl64I9rmzvPMZaZ1TiKoSOVM0BQPuECEs2xFCIg9DqL-kJBJj9mFed3SjUznxDg0v0H8qgbALC5xfQd8pbfKx9Ese7lAetx_5WWygF-f03f6dV_OVu2lV_qh4ros5w-u2T2WvFiI1B1xPcLT1a1YclcPoUEt01QAwdumiICjge17vp0km06TKpyMaB8ckdhLWx7md2fw5zRkltHkkkW3ND_jHHWzumt24cOx1IIIh68qewOz54eSNH2mIWPkogk074gyKnlLPH3vQhiApbLpz_F4rZRRM07RG36TrzMsca1OlAnSk-6KUDXM7pJzj215gPS6F5PUUAa30fZ157fFBY0INp7uwOdWHULmykAqk2f6Jog1knpM_LvGxIDupcIilL1P8oDjxF3bvnRn9CwKG7VnQAEuwFYD_7F1uepJM4VmJxeBxWB35RlYxbDljkncRXUjzLUu4C9H-wcesAzlcQunVNXKh1atXyCdn_pZlHIxc-S8AYVHE2rEZmnuKqbcde7EWgGY-StFE_NaQ539zat-VzLcUXfFGFM6G7dED4WL82CgZUQ2ymQiYB-lP22Vb7EdLfXCyymDf-A2NchA01sp_-faaTZzFDFAfk8Vg3QSQstQG6MVbc49mgTG0BmJ-9tG3HXj_WwLYv4ixCpR7F7kOzOJINrx6GNtKMm6MIq-c3k645NZolvaYvs_jhfQ_Tt6Awiq-J9OXtzvGKbj0p1mptmkOYOFE9qdOs2YhiH3HHIv5yOZA"
    Convert-STSAuthorizationMessage -EncodedMessage $messageToDecode | Out-File -FilePath "c:\temp\decodedMessage.json"
}

# Check the s
function StatusCheck([string]$targetOrgName){
     <#
    .DESCRIPTION
       Get the status of different resources such as EC2 instances, cloud formation stacks in a set of accounts under the target organization 
    .PARAMETER targetOrgName
       Status will be checked in all the accounts under this target organization
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
        $region =Get-DefaultAWSRegion
        
        Write-Output "##################################################################"
        Write-Output ("Student Account : "+$accountInfo.Account)
        $ec2InstanceList=Get-EC2Instance
        foreach($ec2Reservation in $ec2InstanceList){
            foreach($ec2Instance in $ec2Reservation.Instances){
               Write-Output ("EC2 instance : "+$ec2Instance.InstanceId+" : "+$ec2Instance.State.Name.Value)
            }
        }
 
       $CFStackList=Get-CFNStackSummary | Where-Object {$_.StackStatus -ne "DELETE_COMPLETE"} | Sort-Object -Property CreationTime -Descending
        foreach($stack in $CFStackList){
            Write-Output("CloudFormation : "+$stack.StackName+" : "+$stack.StackStatus)
        }

        Write-Output "##################################################################"
    }
}

StatusCheck -targetOrgName "PartnerLabOrg"