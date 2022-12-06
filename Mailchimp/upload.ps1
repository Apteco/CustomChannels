#See https://mailchimp.com/developer/marketing/guides/quick-start/
param([hashtable] $params)

$server = $params['Username'];
$apiKey = $params['Password'];

$path = $params['Path'];
$listName = $params['ListName'];
$urnFieldName = $params['UrnFieldName'];
$emailFieldName = $params['EmailFieldName'];
$communicationKeyFieldName = $params['CommunicationKeyFieldName'];
$transactionType = $params['TransactionType'];  # Replace, Append, Create
$messageName = $params['MessageName'];
$replyToEmail = $params['ReplyToEmail'];
$useDatedList = $params['UseDatedList'];
$debugFile = $params['DebugFile'];
$scriptRoot = $params['ScriptRoot'];
$timeoutInSeconds = 600


if ([string]::IsNullOrEmpty($scriptRoot)) {
	$scriptRoot = $PSScriptRoot
}

. "$scriptRoot\common.ps1"

#Create a dictionary of field name to field value to be uploaded as merge fields for this record
function Get-MergeFields ([object] $item)
{
	$mergeFields=[hashtable]@{}
	
	$item | Get-Member -MemberType NoteProperty | Foreach-Object {

		if ($_.Name -eq $emailFieldName) {
			return
		} elseif ($_.Name -eq $communicationKeyFieldName) {
			return
		} else {
			$mergeFields[$_.Name] = $item | Select -ExpandProperty $_.Name
		}
	}
	return $mergeFields
}

Write-Debug $debugFile "Called upload script with parameters" $params

#For free accounts, Mailchimp only allows one list/audience - so just reuse this and set the given listname as a tag
$firstList = Get-FirstList
$listId = $firstList.id

#Import the data in the file generated by the campaigning engine
$data = [Array]@(Import-csv -Delimiter `t -Path $path -Encoding utf8)
Write-Debug $debugFile "Found ${data.Length} records to update in file ${path}"

#Find any existing segment for the specified list name
$segmentId  = Get-SegmentIdForName $listId $listName
Write-Debug $debugFile "Found segment with id ${segmentId} for name ${listName}"

#If a segment already exists, delete it
if (-Not [string]::IsNullOrEmpty($segmentId)) {
	Invoke-RestMethod -UseBasicParsing -Method 'Delete' -Uri "https://${server}.api.mailchimp.com/3.0/lists/${listId}/segments/${segmentId}" -Headers @{ "Authorization" = "Bearer: $apiKey" }
	Write-Debug $debugFile "Deleted segment id ${segmentId} so we can recreate"
}

#Set up the details to re-create the segment
$createSegmentBody = [hashtable]@{
	"name" = $listName
	"static_segment" = @()
}
$createSegmentBodyJson = $createSegmentBody | ConvertTo-Json

#Recreate the segment with the given name on the default list
$createdSegmentResult = Invoke-RestMethod -UseBasicParsing -Method 'Post' -Uri "https://${server}.api.mailchimp.com/3.0/lists/${listId}/segments" -Headers @{ "Authorization" = "Bearer: $apiKey" } -Body $createSegmentBodyJson
$segmentId = $createdSegmentResult.id
Write-Debug $debugFile "Created segment id ${segmentId} with name ${listName}"

#Create a set of batch operations to POST to Mailchimp all in one go.
$batchOperations = @()

#For each row in the data file
for ($i = 0; $i -lt $data.Length; $i++) {
	
	#If we have no email address, skip
	$item = $data[$i]
	$emailAddress = $item | Select -ExpandProperty $emailFieldName
	if ([string]::IsNullOrEmpty($emailAddress)) {
		continue
	}
	
	#Create a details for adding an email to the list with the given merge field data
	$mergeFields = Get-MergeFields $item
	$createSubscriberBody = [hashtable]@{
		"email_address" = $emailAddress
		"status" = "subscribed"
		"merge_fields" = $mergeFields
	}

	$batchOperations += [hashtable]@{
		"method" = "POST"
		"path" = "/lists/${listId}/members"
		"operation_id" = "${i}-member"
		"body" = $createSubscriberBody | ConvertTo-Json
	}

	#Add the created email to the given segment
	$addToSegmentBody = [hashtable]@{
		"email_address" = $emailAddress
	}

	$batchOperations += [hashtable]@{
		"method" = "POST"
		"path" = "/lists/${listId}/segments/${segmentid}/members"
		"operation_id" = "${i}-segment"
		"body" = $addToSegmentBody | ConvertTo-Json
	}
}

#Create the details to POST all of the above batch operations.
$updateListMembers = [hashtable]@{
	"operations" = $batchOperations
}
$updateListMembersJson = $updateListMembers | ConvertTo-Json
Write-Debug $debugFile "Posting list details to batch endpoint" $updateListMembersJson
$createdBatchResults = Invoke-RestMethod -UseBasicParsing -Method 'Post' -Uri "https://${server}.api.mailchimp.com/3.0/batches" -Headers @{ "Authorization" = "Bearer: $apiKey" } -Body $updateListMembersJson
$createdBatchId = $createdBatchResults.id
Write-Debug $debugFile "Created batch job ${createdBatchId}"

$uploadResults = [hashtable]@{
	"Recipients" = $data.Length
	"RecipientsRejected" = 0
	"TransactionId" = "${createdBatchId}"
}

#Wait for the batch job to complete and return success
for ($i = 0; $i -le $timeoutInSeconds; $i++) {
	$batchStatusResults = Invoke-RestMethod -UseBasicParsing -Uri "https://${server}.api.mailchimp.com/3.0/batches/${createdBatchId}" -Headers @{ "Authorization" = "Bearer: $apiKey" }
	if ($batchStatusResults.status -eq "finished") {
		Write-Debug $debugFile "Batch operation completed after ${i} seconds" $uploadResults
		return $uploadResults
	}
	Start-Sleep -Seconds 1
}

#If the batch job doesn't complete within the given time then log and return an error
Write-Debug $debugFile "Batch operation still hadn't completed after ${timeoutInSeconds} seconds"
return $null