/*
 *********************************************************************************************************************
 * Class: GA_Integration - Google Analytics Integration class.
 * 
 * Version Date	   Author	   Comment
 * ------- ---------- ----------- -----------------------------------------------------
 * 001     08-05-2017 Lee Harding Initial version.
 *********************************************************************************************************************
 */
global class GA_Integration 
{
    /*
     *********************************************************************************************************************
     * Class: GoogleAnalyticsReportResult
     *********************************************************************************************************************
     */
	public class GoogleAnalyticsReportResult
	{
		public String reportName;
		public List<Reports> reports;
	}

    /*
     *********************************************************************************************************************
     * Class: Reports
     *********************************************************************************************************************
     */
	public class Reports
	{
		public Data data;
	}

    /*
     *********************************************************************************************************************
     * Class: Data
     *********************************************************************************************************************
     */
	public class Data
	{
		public List<Rows> rows;
		public List<Metrics> totals;
		public Integer rowCount;
		public List<Metrics> minimums;
		public List<Metrics> maximums;
	}

    /*
     *********************************************************************************************************************
     * Class: Rows
     *********************************************************************************************************************
     */
	public class Rows
	{
		public List<String> dimensions;
		public List<Metrics> metrics;
	}
	
    /*
     *********************************************************************************************************************
     * Class: Metrics
     *********************************************************************************************************************
     */
	public class Metrics
	{
		public List<String> values;
	}





    /*
     *********************************************************************************************************************
     * Method: doReports
     *********************************************************************************************************************
     */
    @AuraEnabled
    webservice static void doReports(String ParentObjectID, String visitorID, String objectType, String triggeredOn)
    {
        // Get all the active reports that have been created (filtered on the object type and trigger)
        List<Google_Analytics_Report__c> lReports = getActiveReports(objectType, triggeredOn);
        
        // Execute the reports, ie. send them to Google.
        List<GoogleAnalyticsReportResult> GAresults = executeAllActiveReports(visitorID, lReports);
        
        // Store the Google Analytics Results into the Salesforce Object
        parseResults(ParentObjectID, visitorID, GAresults);
    }





    /*
     *********************************************************************************************************************
     * Method: parseResults
     *********************************************************************************************************************
     */
     static void parseResults(String ParentObjectID, String visitorID, List<GoogleAnalyticsReportResult> GAresultSet)
     {
        // delete the existing GA data.
        system.debug('parseResults|Delete|ParentObject='+ParentObjectID);
		List<Google_Analytics_Result__c> toDelete = [SELECT Id, Name FROM Google_Analytics_Result__c WHERE Parent_Object__c=:ParentObjectID];
        delete toDelete;

     	List<Google_Analytics_Result__c> lgar = new List<Google_Analytics_Result__c>();
     	
        // Process each resultset.
        for(GoogleAnalyticsReportResult GAResult : GAresultSet)
        {
        	for(Reports r: GAResult.reports)
        	{
        		for(Rows rows: r.data.rows)
        		{
       				Google_Analytics_Result__c gar = new Google_Analytics_Result__c();
       				
       				gar.name = GAResult.reportName;
       				gar.Data_Group__c = rows.dimensions[0];
       				gar.Data_Name__c = rows.dimensions[1];
       				gar.Data_Value__c = rows.metrics[0].values[0];
       				gar.Parent_Object__c = ParentObjectID;
       				
       				// Using the parent object ID, we can determine what type of object it is.
       				Id sId = Id.valueOf(ParentObjectID);
       				gar.Parent_Object_Type__c = sId.getSObjectType().getDescribe().getName();
       				
       				lgar.add(gar);
        		}
        	}
        }
		insert lgar;
     }





    /*
     *********************************************************************************************************************
     * Method: executeAllActiveReports
     *********************************************************************************************************************
     */
    static List<GoogleAnalyticsReportResult> executeAllActiveReports(String sVisitorID, List<Google_Analytics_Report__c> lgoogleReports)
    {
    	List<GoogleAnalyticsReportResult> GAresults = new List<GoogleAnalyticsReportResult>();
    	
        // Process each report.
        for(Google_Analytics_Report__c googleReport : lgoogleReports)
        {
            system.debug('executeAllActiveReports|Executing Report = '+googleReport.Name);
            GAresults.add(JSONtoObject(googleReport, executeGoogleAnalyticsReport(sVisitorID, googleReport)));
        }
        
        return GAResults;
    }
    




    /*
     *********************************************************************************************************************
     * Method: JSONtoObject
     *********************************************************************************************************************
     */
    static GoogleAnalyticsReportResult JSONtoObject(Google_Analytics_Report__c googleReport, String sResult)
    {
        // Create a JSON Parser so we can extract the report data (We could use the JSON deserialization, but you have to be sure what you've got in your JSON.
        JSONParser parser = JSON.createParser(sResult);
    	
        List<Google_Analytics_Result__c> googleAnalyticsResults = new List<Google_Analytics_Result__c>();
        
       	// Read entire row object, including its array of line items.
        GoogleAnalyticsReportResult rep = (GoogleAnalyticsReportResult)parser.readValueAs(GoogleAnalyticsReportResult.class);
        
        // Add the report name
        rep.reportName = googleReport.Name;
                    
        return rep;
    }





    /*
     *********************************************************************************************************************
     * Method: getActiveReports
     *********************************************************************************************************************
     */
    static List<Google_Analytics_Report__c> getActiveReports(String objectType, String triggeredOn)
    {
        // Retrieve the reports that will be executed.
		List<Google_Analytics_Report__c> lReports = [SELECT 	Google_Identity_Platform__c, 
                                                     			Name,
                                                                Id, 
                                                                HTTP_Method__c, 
                                                                HTTP_Header_Content_Type__c, 
                                                                HTTP_End_Point__c,
                                                                Report_Request__c 
                                                        FROM 	Google_Analytics_Report__c
                                                        WHERE	Active__c=TRUE]; 
       	system.debug('getActiveReports|Reports found:');
        
        // Do any pre-processing here.
        for(Google_Analytics_Report__c googleReport : lReports)
        {
            system.debug('getActiveReports|Report = '+googleReport.Name);
        }
        
        return lReports;
    }





     /*
     *********************************************************************************************************************
     * Method: executeGoogleAnalyticsReport
     *
     * Method to request a report from Google Analytics for a specific visitor. This currently has a hard-coded JSON for 
     * the report request. In the future, this could be changed to load the JSON given a report ID so that the JSON could
     * be created in a more user-friendly manner and stored, making this function generic. As this method simply returns
     * a JSON for the results is would be safe to make generic (i.e. pass any JSON report request and return the results
     * as Google Analytcs provides them.)
     * 
     * Parameters
     * ----------
     * 1 - String - Visitor ID, a unique string that is captured in Google Analytics for each individual user so that we can filer the analytics down
     * to a specific visitor.
     * 
     * Returns
     * -------
     * String - JSON containing the results of the Google Analytics report request.
      *********************************************************************************************************************
     */
    webservice static String executeGoogleAnalyticsReport(String visitorID, Google_Analytics_Report__c googleReport)
    {
        Google_Identity_Platform__c googleIdentity;
            
        // Retrieve the Google Identity Platform information to use with this report.
		List<Google_Identity_Platform__c> lGoogleIdentity = [SELECT Name,
                                                             		Claim_Set_aud__c, 
                                                     				Claim_Set_exp__c,
                                                                	Claim_Set_iat__c, 
                                                                	Claim_Set_ISS__c, 
                                                                	Claim_Set_Scope__c, 
                                                                	Header_Format__c,
                                                                	HTTP_End_Point__c,
                                                       				HTTP_Header__c,
                                                       				HTTP_Method__c,
                                                       				Signature_Private_Key__c
                                                        	FROM	Google_Identity_Platform__c
                                                        	WHERE	id=:googleReport.Google_Identity_Platform__c]; 
        
        // Check that we have a Identity to use, we should only have 1.
        if(lGoogleIdentity.size() == 1)
        {
            // Store the Google Identity
            googleIdentity = lGoogleIdentity.get(0);
       		system.debug('executeGoogleAnalyticsReport|Identity found:' +googleIdentity.Name);
        }
        else
        {
       		system.debug('executeGoogleAnalyticsReport|Identity NOT found.');
        }
        
        
        // To test/create JSON, use https://developers.google.com/analytics/devguides/reporting/core/v4/rest/v4/reports/batchGet#try-it
		String json = googleReport.Report_Request__c;
		
        // Update the JSON to add the visitor ID that we'll need to filter the report in Google Analytics.
        json = json.replace('%VISITOR_ID%', visitorID);
        
        // Create the HTTP, request and response objects that we'll use.
        Http h = new Http();
        HttpRequest req = new HttpRequest();
        HttpResponse res = new HttpResponse();
        
        //Set-up the request details.
        req.setEndpoint(googleReport.HTTP_End_Point__c);
        req.setMethod(googleReport.HTTP_Method__c);
		req.setHeader('Content-Type',googleReport.HTTP_Header_Content_Type__c);

        req.setHeader('Content-Length', ''+json.length());
        req.setHeader('Accept-Encoding','gzip, deflate');
        req.setHeader('Authorization', 'Bearer ' + getGoogleAccessToken(googleIdentity));

        req.setBody(json);

        //Send the request via the HTTP object capturing the response.
        res = h.send(req);       
        
        // Process the response if successful (https://developers.google.com/analytics/devguides/reporting/core/v4/errors)
        // This could be a exception handled from here, but for the sake of the PoC, we'll keep it simple.
		if(res.getStatusCode() == 200)
        {
        	System.debug('executeGoogleAnalyticsReport|Success|'+res.getStatusCode());
            
            // Something could be done here.
        }
        else
        {
            // it's not a 200...so Google API was not happy; but we could handle some errors better, such as
            // 401 errors (unauthenticated) by requested a new access token and trying again because our access token may have expired.
            // or 429 errors (resource exhausted) by implementing exponential backoff so we stop overloading Google API (LIMITS!!!)
            System.debug('executeGoogleAnalyticsReport|Error|'+res.getStatusCode());
            
            // Handle the errors if appropriate.
        }
        
        // We'll just return the body whether success or otherwise.
        return res.getBody();
    }





    /*
     *********************************************************************************************************************
     * Method: getGoogleAccessToken
     *
     * Method to attain access to the Google API. Currently this uses OAuth2, which may change in the future. In the mean
     * time, this method uses the private key configured in the API management tool to request an Access Token for 
     * subsequent API calls. This needs some configuration at the Google end of things to make sure you are enabling the 
     * correct API etc. I have left plenty of System.Debug around so that it is easy to trace what is going on.
     * 
     * Paramaters
     * ----------
     * None
     * 
     * Returns
     * ------- 
     * 1 - String - Access Token to be used in subsequent calls to Google API.
      *********************************************************************************************************************
     */
 	webservice static String getGoogleAccessToken(Google_Identity_Platform__c gip)
    {
     	String access_token;
        String token_type;
        String expires_in;
        
        /*
         * Need to do a check here to determine if we already have an access token so we don't need to keep
         * asking for one. This will  need to be a list as there could be multiple access tokens if multiple
         * reports are using different GA credentials
         */
        
        /*
         * Google Identity Platform 
         * ========================
         * To access the Google Analytics Reporting API, we need to use the Google Identity Platform.
         * The GIP uses OAuth2, so sending a private key and it being valid, will return is an access
         * token that we can use for all subsequent requests to the desired scope. GIP Requires a JSON 
         * Web Token (JWT), made up of a Header, Claim Set and Signature.
		 */

        Http h = new Http();
		HttpRequest req = new HttpRequest();
		HttpResponse res = new HttpResponse();

        req.setEndpoint(gip.HTTP_End_Point__c);
		req.setMethod(gip.HTTP_Method__c);
		req.setHeader('Content-Type',gip.HTTP_Header__c);
		

        /* Step 1 - Create the Header.
         * ---------------------------
         * The header consists of two fields that indicate the signing algorithm and the format of the 
		 * assertion. Both fields are mandatory, and each field has only one value. As additional algorithms
		 * and formats are introduced, this header will change accordingly.
		 *
		 * Service accounts rely on the RSA SHA-256 algorithm and the JWT token format. As a result, the 
		 * JSON representation of the header is as follows:
		 *
		 * {"alg":"RS256","typ":"JWT"}
         */
		String header = gip.Header_Format__c;
		String header_encoded = EncodingUtil.base64Encode(blob.valueof(header));

        /*
         * Step 2 - Create the Claim Set.
         * ------------------------------
         * The JWT claim set contains information about the JWT, including the permissions being 
         * requested (scopes), the target of the token, the issuer, the time the token was issued, 
         * and the lifetime of the token. Most of the fields are mandatory. Like the JWT header, 
         * the JWT claim set is a JSON object and is used in the calculation of the signature.
         * Like the JWT header, the JWT claim set should be serialized to UTF-8 and Base64url-safe encoded
		 */	
		String claim_set = '{"iss":"' + gip.Claim_Set_ISS__c + '"';			// Email address of the Service Account
			   claim_set += ',"scope":"' + gip.Claim_Set_Scope__c + '"';		// A space-delimited list of the permissions that the application requests.
			   claim_set += ',"aud":"' + gip.Claim_Set_aud__c + '"'; 			// A descriptor of the intended target of the assertion. When making an access token request this value is always https://www.googleapis.com/oauth2/v4/token.
			   claim_set += ',"exp":"' + datetime.now().addHours(1).getTime()/1000; // The expiration time of the assertion, specified as seconds since 00:00:00 UTC, January 1, 1970. This value has a maximum of 1 hour after the issued time.
			   claim_set += '","iat":"' + datetime.now().getTime()/1000 + '"}'; 	//The time the assertion was issued, specified as seconds since 00:00:00 UTC, January 1, 1970.
				
        String claim_set_encoded = EncodingUtil.base64Encode(blob.valueof(claim_set)); // Enclose the Claim Set because we're going to transmit it across the Internet.
        
		/*
         * Step 3 - Create the Signature.
         * ------------------------------
         * JSON Web Signature (JWS) is the specification that guides the mechanics of generating 
         * the signature for the JWT. The input for the signature is the byte array of the following content:
         * {Base64url encoded header}.{Base64url encoded claim set}
         * The signing algorithm in the JWT header must be used when computing the signature. The only signing 
         * algorithm supported by the Google OAuth 2.0 Authorization Server is RSA using SHA-256 hashing algorithm. 
         * This is expressed as RS256 in the alg field in the JWT header.
         */
		String signature_encoded = header_encoded + '.' + claim_set_encoded; // Add the Header and Claim Set to the Signature
		signature_encoded = signature_encoded.replaceAll('=',''); // Remove any "="
		String signature_encoded_url = EncodingUtil.urlEncode(signature_encoded,'UTF-8'); // URL encode the signature for safe transmission.
		blob signature_blob =   blob.valueof(signature_encoded_url);
		blob private_key = EncodingUtil.base64Decode(gip.Signature_Private_Key__c); // Decode the private key
		
		String signature_blob_string = EncodingUtil.base64Encode(Crypto.sign('RSA-SHA256', signature_blob, private_key)); // Sign the UTF-8 representation of the input using SHA256withRSA (also known as RSASSA-PKCS1-V1_5-SIGN with the SHA-256 hash function) with the private key obtained from the Google API Console. The output will be a byte array.
		String JWT = signature_encoded + '.' + signature_blob_string; //The signature must then be Base64url encoded. The header, claim set, and signature are concatenated together with a period (.) character. The result is the JWT. 
		JWT = JWT.replaceAll('=','');

        /*
         * After generating the signed JWT, we can use it to request an access token. This access token request 
         * is an HTTPS POST request, and the body is URL encoded.
         */
        String grant_string= 'urn:ietf:params:oauth:grant-type:jwt-bearer';
		req.setBody('grant_type=' + EncodingUtil.urlEncode(grant_string, 'UTF-8') + '&assertion=' + EncodingUtil.urlEncode(JWT, 'UTF-8'));
		res = h.send(req);

        /*
         * We can now look at the response from Google to determine the correct course of action.
         */
		String response_debug = res.getBody() +' '+ res.getStatusCode();
		if(res.getStatusCode() == 200) // informtaion on Error codes here: https://developers.google.com/drive/v3/web/handle-errors
        {
       		System.debug('getGoogleAccessToken|Success');

            // We have JSON returned to us, so we need to parse it. We're looking for access_token primarily.
    		JSONParser parser = JSON.createParser(res.getBody());
    		while (parser.nextToken() != null) 
            {
        		if ((parser.getCurrentToken() == JSONToken.FIELD_NAME) && (parser.getText() == 'access_token'))
            	{
            		// Move to the value.
            		parser.nextToken();
            		// Get the access_token
                    access_token = parser.getText();
            		System.debug('getGoogleAccessToken|Access Token|' + Access_Token );
        		} // just debug stuff below, not needed for this to work, but interesting to see information in Debug.
                if ((parser.getCurrentToken() == JSONToken.FIELD_NAME) && (parser.getText() == 'token_type'))
                {
                    // Move to the value.
                    parser.nextToken();
                    // Get the token type.
                    token_type = parser.getText();
             		System.debug('getGoogleAccessToken|Token Type|' + token_type );
				}
                if ((parser.getCurrentToken() == JSONToken.FIELD_NAME) && (parser.getText() == 'expires_in'))
                {
                    // Move to the value.
                    parser.nextToken();
                    
                    // Get the expires_in.
                    expires_in = parser.getText();
                    System.debug('getGoogleAccessToken|Expires In|' + expires_in );
                }
    		}
		}
        else
        {
            System.debug('getGoogleAccessToken|Error|'+res.getStatusCode());
        }
        
        /*
         * We have the access token or not, so let's return what we have.
         */
        return access_token;
    }
    

}